#include "anytime_trace.hpp"
#include <ghost/solver.hpp>
#include <ghost/model_builder.hpp>
#include <ghost/constraint.hpp>
#include <ghost/objective.hpp>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <set>
#include <memory>
struct Node {int id,demand,pickup;double x,y,early,late,service;};
struct Data {int capacity,fleet;double big_m;std::vector<Node> nodes;std::vector<std::vector<double>> distances;};
std::pair<double,double> evaluate(const Data& d,const std::vector<ghost::Variable*>& values) {
    double error=0,distance=0,time=d.nodes[0].early;int load=0,previous=0,used=0;bool nonempty=false;std::set<int> seen;
    auto finish=[&](){if(!nonempty)return;used++;double travel=d.distances[previous][0];distance+=travel;
        error+=std::max(0.,time+d.nodes[previous].service+travel-d.nodes[0].late)+std::abs(load);
        time=d.nodes[0].early;load=0;previous=0;seen.clear();nonempty=false;};
    for(auto var:values) {
        int index=var->get_value()-1;if(index>=int(d.nodes.size())){finish();continue;}
        const auto& v=d.nodes[index];double travel=d.distances[previous][index];distance+=travel;
        time=std::max(v.early,time+d.nodes[previous].service+travel);error+=std::max(0.,time-v.late);
        load+=v.demand;error+=std::max(0,-load)+std::max(0,load-d.capacity);
        if(v.pickup>0 && !seen.contains(v.pickup))error+=1;
        seen.insert(v.id);previous=index;nonempty=true;
    }
    finish();return {error,used*d.big_m+distance};
}
class Constraint:public ghost::Constraint {
    std::shared_ptr<const Data> d;
    double required_error(const std::vector<ghost::Variable*>& v)const override{return evaluate(*d,v).first;}
public:Constraint(const std::vector<ghost::Variable>& v,std::shared_ptr<const Data> data):ghost::Constraint(v),d(data){}
};
class Objective:public ghost::Minimize {
    std::shared_ptr<const Data> d;
    double required_cost(const std::vector<ghost::Variable*>& v)const override{return evaluate(*d,v).second;}
public:Objective(const std::vector<ghost::Variable>& v,std::shared_ptr<const Data> data):Minimize(v,"fleet then distance"),d(data){}
};
class Builder:public ghost::ModelBuilder {
    std::shared_ptr<const Data> d;
public:Builder(std::shared_ptr<const Data> data):ModelBuilder(true),d(data){}
    void declare_variables()override{int n=d->nodes.size()+d->fleet-2;for(int i=0;i<n;i++)create_variable(2,n,"token"+std::to_string(i),i);}
    void declare_constraints()override{constraints.emplace_back(std::make_shared<Constraint>(variables,d));}
    void declare_objective()override{objective=std::make_shared<Objective>(variables,d);}
};
int main(int argc,char** argv) {
    if(argc!=4 && argc!=5)return 2;
    int workers=argc==5 ? std::stoi(argv[4]) : 4;
    if(workers!=1 && workers!=2 && workers!=4)return 5;
    benchmark_trace::reset();
    auto d=std::make_shared<Data>();std::ifstream in(argv[1]);std::string version;int n;
    in>>version>>n>>d->capacity>>d->fleet;if(version!="pdptw/1")return 3;
    for(int i=0;i<n;i++){Node v;in>>v.id>>v.x>>v.y>>v.demand>>v.early>>v.late>>v.service>>v.pickup;d->nodes.push_back(v);}
    if(!in)return 4;double max=0;d->distances.resize(n,std::vector<double>(n));
    for(int i=0;i<n;i++)for(int j=0;j<n;j++){double v=std::hypot(d->nodes[i].x-d->nodes[j].x,d->nodes[i].y-d->nodes[j].y);d->distances[i][j]=v;max=std::max(max,v);}
    d->big_m=2*(n-1)*max+1;Builder builder(d);ghost::Solver solver(builder);
    ghost::Options options;options.parallel_runs=workers>1;options.number_threads=workers;
    double budget=std::stod(argv[2]),cost;std::vector<int> values;
    benchmark_trace::solve_origin=std::chrono::steady_clock::now();
    double build=std::chrono::duration<double>(benchmark_trace::solve_origin-benchmark_trace::origin).count();
    solver.fast_search(cost,values,budget*1e6,options);
    double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-benchmark_trace::solve_origin).count();
    std::ofstream out(argv[3]);out<<std::setprecision(17);
    out<<"schema = \"incumbent-trace/1\"\nengine = \"ghost_native_cpp\"\nprofile = \"default_permutation\"\nclock = \"monotonic\"\ntiming_available = true\nproof_time_available = false\nseed_controlled = false\nthreads = "<<workers<<"\nparallelism = \"native parallel searches\"\n";
    out<<"budget_seconds = "<<budget<<"\nbuild_seconds = "<<build<<"\nsolve_call_seconds = "<<elapsed<<"\nfound = "<<(benchmark_trace::events.empty()?"false":"true")<<"\n";
    if(benchmark_trace::events.empty())out<<"events = []\n";
    for(const auto& e:benchmark_trace::events){out<<"\n[[events]]\nphase = \"search\"\nelapsed_seconds = "<<e.elapsed<<"\nsolve_seconds = "<<e.solve<<"\nobjective = "<<e.cost<<"\nvalues = [";
        for(size_t i=0;i<e.values.size();i++){if(i)out<<", ";out<<e.values[i];}out<<"]\n";}
}
