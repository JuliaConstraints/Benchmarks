#include <ghost/solver.hpp>
#include <ghost/model_builder.hpp>
#include <ghost/constraint.hpp>
#include <ghost/objective.hpp>
#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <set>
#include <vector>
#include <chrono>

struct Node { int id,demand,pickup;double x,y,early,late,service; };
struct Data { int capacity;std::vector<Node> nodes; };
std::pair<double,double> evaluate(const Data& d,const std::vector<ghost::Variable*>& v) {
    double error=0,cost=0,time=d.nodes[0].early;int load=0,previous=0;std::set<int> seen;
    for(auto var:v) {
        int index=var->get_value()-1;const auto& node=d.nodes[index];const auto& prev=d.nodes[previous];
        double travel=std::hypot(node.x-prev.x,node.y-prev.y);cost+=travel;
        time=std::max(node.early,time+prev.service+travel);error+=std::max(0.,time-node.late);
        load+=node.demand;error+=std::max(0,-load)+std::max(0,load-d.capacity);
        if(node.pickup>0 && !seen.contains(node.pickup))error+=1;
        if(seen.contains(node.id))error+=1;seen.insert(node.id);previous=index;
    }
    double travel=std::hypot(d.nodes[previous].x-d.nodes[0].x,d.nodes[previous].y-d.nodes[0].y);cost+=travel;
    error+=std::max(0.,time+d.nodes[previous].service+travel-d.nodes[0].late)+std::abs(load);
    return {error,cost};
}
class RouteConstraint:public ghost::Constraint {
    std::shared_ptr<const Data> data;
    double required_error(const std::vector<ghost::Variable*>& v)const override{return evaluate(*data,v).first;}
public:RouteConstraint(const std::vector<ghost::Variable>& v,std::shared_ptr<const Data> d):Constraint(v),data(d){}
};
class Distance:public ghost::Minimize {
    std::shared_ptr<const Data> data;
    double required_cost(const std::vector<ghost::Variable*>& v)const override{return evaluate(*data,v).second;}
public:Distance(const std::vector<ghost::Variable>& v,std::shared_ptr<const Data> d):Minimize(v,"route distance"),data(d){}
};
class Builder:public ghost::ModelBuilder {
    std::shared_ptr<const Data> data;
public:
    Builder(std::shared_ptr<const Data> d):ModelBuilder(true),data(d){}
    void declare_variables()override{
        // GHOST's permutation search preserves the initial multiset: it must
        // contain each visit once before the engine starts shuffling it.
        for(int i=0;i<int(data->nodes.size())-1;i++)
            create_variable(2,data->nodes.size()-1,"visit"+std::to_string(i),i);
    }
    void declare_constraints()override{constraints.emplace_back(std::make_shared<RouteConstraint>(variables,data));}
    void declare_objective()override{objective=std::make_shared<Distance>(variables,data);}
};
int main(int argc,char** argv) {
    if(argc!=3)return 2;
    std::ifstream in(argv[1]);int n;auto data=std::make_shared<Data>();in>>n>>data->capacity;
    for(int i=0;i<n;i++){Node v;in>>v.id>>v.x>>v.y>>v.demand>>v.early>>v.late>>v.service>>v.pickup;data->nodes.push_back(v);}
    if(!in)return 3;
    for(int attempt=0;attempt<=3;attempt++){
        auto start=std::chrono::steady_clock::now();Builder builder(data);ghost::Solver solver(builder);
        ghost::Options options;options.parallel_runs=true;options.number_threads=4;
        double build=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
        double cost=0;std::vector<int> route;start=std::chrono::steady_clock::now();
        bool found=solver.fast_search(cost,route,attempt==0?250000.:2000000.,options);
        double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
        if(attempt==0)continue;
        std::ofstream out(std::string(argv[2])+"/ghost_native_cpp-"+std::to_string(attempt)+".toml");out<<std::setprecision(17);
        out<<"engine = \"ghost_native_cpp\"\nvalidated = false\nfound = "<<(found?"true":"false")<<"\nroute = [";
        for(size_t i=0;i<route.size();i++){if(i)out<<", ";out<<route[i];}
        out<<"]\nreported_distance = "<<cost<<"\nsolve_call_seconds = "<<elapsed<<"\nbuild_seconds = "<<build<<"\nthreads = 4\nbudget_seconds = 2.0\nseed_controlled = false\n";
        std::cout<<"GHOST native run "<<attempt<<" found="<<found<<" distance="<<cost<<" seconds="<<elapsed<<std::endl;
    }
}
