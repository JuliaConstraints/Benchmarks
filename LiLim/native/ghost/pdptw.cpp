// Li-Lim adapter for unmodified upstream GHOST; observations are feasible candidates.
#include "solver.hpp"
#include "model_builder.hpp"
#include "constraint.hpp"
#include "objective.hpp"
#include <fstream>
#include <iomanip>
#include <mutex>
#include <memory>
#include <set>
#include <ctime>
#include <atomic>
using Clock=std::chrono::steady_clock;
struct Node {int id,demand,pickup;double x,y,early,late,service;};
struct Data {int capacity,fleet;double big_m;std::vector<Node> nodes;std::vector<std::vector<double>> distances;std::vector<int> initial;};
struct Score {double error,distance;int vehicles;};
Data read_data(const char* path) {
    Data d;std::ifstream in(path);std::string schema;int n;in>>schema>>n>>d.capacity>>d.fleet;
    if(schema!="lilim-common-start/1")throw std::runtime_error("wrong input schema");
    for(int i=0;i<n;i++){Node v;in>>v.id>>v.x>>v.y>>v.demand>>v.early>>v.late>>v.service>>v.pickup;d.nodes.push_back(v);}
    for(int k=0;k<d.fleet;k++){int size;in>>size;for(int j=0;j<size;j++){int id;in>>id;d.initial.push_back(id);}if(k+1<d.fleet)d.initial.push_back(n+k+1);}
    if(!in)throw std::runtime_error("incomplete input");
    double maximum=0;d.distances.resize(n,std::vector<double>(n));
    for(int i=0;i<n;i++)for(int j=0;j<n;j++){double v=std::hypot(d.nodes[i].x-d.nodes[j].x,d.nodes[i].y-d.nodes[j].y);d.distances[i][j]=v;maximum=std::max(maximum,v);}
    d.big_m=2*(n-1)*maximum+1;return d;
}
Score evaluate(const Data& d,const std::vector<int>& values) {
    const int n=d.nodes.size(),N=n+d.fleet-2;
    if(int(values.size())!=N)return {INFINITY,INFINITY,0};
    std::vector<bool> unique(N+2),seen(n+1);double error=0,distance=0,time=d.nodes[0].early;
    int load=0,previous=0,used=0;bool nonempty=false;
    auto finish=[&](){if(!nonempty)return;used++;double travel=d.distances[previous][0];distance+=travel;
        error+=std::max(0.,time+d.nodes[previous].service+travel-d.nodes[0].late-1e-8)+std::abs(load);
        time=d.nodes[0].early;load=0;previous=0;std::fill(seen.begin(),seen.end(),false);nonempty=false;};
    for(int id:values){if(id<2||id>N+1)return {INFINITY,INFINITY,0};if(unique[id])error+=1;unique[id]=true;
        int index=id-1;if(index>=n){finish();continue;}
        const auto& v=d.nodes[index];double travel=d.distances[previous][index];distance+=travel;
        time=std::max(v.early,time+d.nodes[previous].service+travel);error+=std::max(0.,time-v.late-1e-8);
        load+=v.demand;error+=std::max(0,-load)+std::max(0,load-d.capacity);
        if(v.pickup>0&&!seen[v.pickup])error+=1;seen[id]=true;previous=index;nonempty=true;
    }
    finish();return {error,distance,used};
}
struct Event {double seconds;Score score;std::vector<int> values;};
struct Trace {
    Clock::time_point origin;double budget,best=INFINITY;std::mutex mutex;
    std::vector<Event> events;
    std::atomic<std::uint64_t> objective_evaluations{0};
    void observe(const Data& d,const std::vector<int>& values,const Score& s){
        if(s.error!=0)return;std::lock_guard<std::mutex> lock(mutex);
        double cost=d.big_m*s.vehicles+s.distance;if(cost>=best)return;
        double t=std::chrono::duration<double>(Clock::now()-origin).count();if(t>budget)return;
        best=cost;events.push_back({t,s,values});
    }
};
std::vector<int> tokens(const std::vector<ghost::Variable*>& values){std::vector<int> v;v.reserve(values.size());for(auto p:values)v.push_back(p->get_value());return v;}
class Constraint:public ghost::Constraint {
    std::shared_ptr<const Data> d;
    double required_error(const std::vector<ghost::Variable*>& v)const override{return evaluate(*d,tokens(v)).error;}
public:Constraint(const std::vector<ghost::Variable>& v,std::shared_ptr<const Data> data):ghost::Constraint(v),d(data){}
};
class Objective:public ghost::Minimize {
    std::shared_ptr<const Data> d;std::shared_ptr<Trace> trace;
    double required_cost(const std::vector<ghost::Variable*>& v)const override{trace->objective_evaluations.fetch_add(1,std::memory_order_relaxed);auto values=tokens(v);auto s=evaluate(*d,values);trace->observe(*d,values,s);return d->big_m*s.vehicles+s.distance;}
public:Objective(const std::vector<ghost::Variable>& v,std::shared_ptr<const Data> data,std::shared_ptr<Trace> t):Minimize(v,"fleet then distance"),d(data),trace(t){}
};
class Builder:public ghost::ModelBuilder {
    std::shared_ptr<const Data> d;std::shared_ptr<Trace> trace;
public:Builder(std::shared_ptr<const Data> data,std::shared_ptr<Trace> t):ModelBuilder(true),d(data),trace(t){}
    void declare_variables()override{int n=d->initial.size();for(int i=0;i<n;i++)create_variable(2,n,"token"+std::to_string(i),d->initial[i]-2);}
    void declare_constraints()override{constraints.emplace_back(std::make_shared<Constraint>(variables,d));}
    void declare_objective()override{objective=std::make_shared<Objective>(variables,d,trace);}
};
double cpu(){timespec s;clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&s);return s.tv_sec+s.tv_nsec/1e9;}
struct Trial {std::shared_ptr<Trace> trace;double wall,cpu_seconds,build;};
Trial solve(const char* input,double budget,int workers){
    auto trace=std::make_shared<Trace>();trace->origin=Clock::now();trace->budget=budget;double c=cpu();
    auto d=std::make_shared<Data>(read_data(input));trace->observe(*d,d->initial,evaluate(*d,d->initial));
    Builder builder(d,trace);ghost::Solver solver(builder);ghost::Options options;
    options.custom_starting_point=true;options.parallel_runs=workers>1;options.number_threads=workers;
    double build=std::chrono::duration<double>(Clock::now()-trace->origin).count(),cost;
    std::vector<int> values;solver.fast_search(cost,values,std::max(0.,budget-build)*1e6,options);
    return {trace,std::chrono::duration<double>(Clock::now()-trace->origin).count(),cpu()-c,build};
}
int main(int argc,char** argv){
    try {
        if(argc==5&&std::string(argv[1])=="evaluate"){
            auto d=read_data(argv[2]);std::ifstream in(argv[3]);std::ofstream out(argv[4]);out<<std::setprecision(17);
            std::vector<int> values(d.initial.size());while(in>>values[0]){for(size_t i=1;i<values.size();i++)in>>values[i];if(!in)return 4;auto s=evaluate(d,values);out<<s.error<<' '<<s.vehicles<<' '<<s.distance<<'\n';}return 0;
        }
        if(argc!=5)return 2;double budget=std::stod(argv[2]);int workers=std::stoi(argv[3]);
        if(!(workers==1||workers==2||workers==4||workers==8||workers==16)||budget<=0)return 3;
        for(int pass=0;pass<2;pass++)solve(argv[1],1.,workers);
        std::ofstream out(argv[4]);out<<std::setprecision(17);
        out<<"schema = \"li-lim-ghost-native/1\"\nseed_controlled = false\nthreads = "<<workers<<"\nbudget_seconds = "<<budget<<"\nobservation = \"feasible objective candidates, not acceptance callbacks\"\n";
        for(int repetition=1;repetition<=3;repetition++){
            auto t=solve(argv[1],budget,workers);
            out<<"\n[[trials]]\nrepetition = "<<repetition<<"\nwall_seconds = "<<t.wall<<"\nprocess_cpu_seconds = "<<t.cpu_seconds<<"\nmean_active_cpus = "<<t.cpu_seconds/t.wall<<"\nbuild_seconds = "<<t.build<<"\n";
            out<<"objective_evaluations = "<<t.trace->objective_evaluations.load()<<"\n";
            if(t.trace->events.empty())out<<"trajectory = []\n";
            for(auto& e:t.trace->events){out<<"\n[[trials.trajectory]]\nseconds = "<<e.seconds<<"\nvehicles = "<<e.score.vehicles<<"\ndistance = "<<e.score.distance<<"\nvalues = [";for(size_t i=0;i<e.values.size();i++){if(i)out<<", ";out<<e.values[i];}out<<"]\n";}
            out.flush();
        }
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
