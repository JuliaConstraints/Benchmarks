package bench;

import java.util.*;
import java.nio.file.*;
import java.time.Duration;
import java.math.BigDecimal;
import ai.timefold.solver.core.api.domain.entity.PlanningEntity;
import ai.timefold.solver.core.api.domain.common.PlanningId;
import ai.timefold.solver.core.api.domain.variable.*;
import ai.timefold.solver.core.api.domain.valuerange.ValueRangeProvider;
import ai.timefold.solver.core.api.domain.solution.*;
import ai.timefold.solver.core.api.score.HardSoftScore;
import ai.timefold.solver.core.api.score.HardSoftBigDecimalScore;
import ai.timefold.solver.core.api.score.calculator.EasyScoreCalculator;
import ai.timefold.solver.core.api.solver.*;
import ai.timefold.solver.core.config.solver.SolverConfig;

/** Native domain adapters only; all experiment orchestration lives in Julia. */
public class Smoke {
    @PlanningEntity public static class Item {
        @PlanningId public int id;
        public int weight, profit;
        @PlanningVariable public Boolean selected;
        public Item() {}
        Item(int id,int w,int p) { this.id=id; weight=w; profit=p; }
    }
    @PlanningSolution public static class Bag {
        @PlanningEntityCollectionProperty public List<Item> items;
        @ValueRangeProvider public List<Boolean> choices=List.of(false,true);
        @PlanningScore public HardSoftScore score;
        public int capacity;
        public Bag() {}
    }
    public static class BagScore implements EasyScoreCalculator<Bag,HardSoftScore> {
        public HardSoftScore calculateScore(Bag b) {
            int weight=0,profit=0;
            for(Item i:b.items) if(Boolean.TRUE.equals(i.selected)) { weight+=i.weight; profit+=i.profit; }
            return HardSoftScore.of(-Math.max(0,weight-b.capacity),profit);
        }
    }
    public static class Visit {
        @PlanningId public int id;
        public double x,y,early,late,service;
        public int demand,pickup;
        public Visit() {}
    }
    @PlanningEntity public static class Route {
        @PlanningId public int id=1;
        @PlanningListVariable public List<Visit> visits=new ArrayList<>();
        public Route() {}
    }
    @PlanningSolution public static class Routing {
        @PlanningEntityCollectionProperty public List<Route> routes;
        @ProblemFactCollectionProperty @ValueRangeProvider public List<Visit> visits;
        @ProblemFactProperty public Visit depot;
        @PlanningScore public HardSoftBigDecimalScore score;
        public int capacity;
        public Routing() {}
    }
    public static class RouteScore implements EasyScoreCalculator<Routing,HardSoftBigDecimalScore> {
        public HardSoftBigDecimalScore calculateScore(Routing p) {
            double error=0,distance=0;
            for(Route r:p.routes) {
                Visit previous=p.depot;double time=p.depot.early;int load=0;
                Set<Integer> seen=new HashSet<>();
                for(Visit v:r.visits) {
                    double travel=Math.hypot(v.x-previous.x,v.y-previous.y);distance+=travel;
                    time=Math.max(v.early,time+previous.service+travel);
                    error+=Math.max(0,time-v.late);
                    load+=v.demand;error+=Math.max(0,-load)+Math.max(0,load-p.capacity);
                    if(v.pickup>0 && !seen.contains(v.pickup)) error+=1;
                    seen.add(v.id);previous=v;
                }
                double travel=Math.hypot(previous.x-p.depot.x,previous.y-p.depot.y);
                distance+=travel;error+=Math.max(0,time+previous.service+travel-p.depot.late)+Math.abs(load);
            }
            return HardSoftBigDecimalScore.of(BigDecimal.valueOf(-error),BigDecimal.valueOf(-distance));
        }
    }
    static SolverConfig config(Class<?> solution,Class<?> entity,Class score,long seed,double seconds) {
        return new SolverConfig().withSolutionClass(solution).withEntityClasses(entity)
            .withEasyScoreCalculatorClass(score).withRandomSeed(seed)
            .withTerminationSpentLimit(Duration.ofMillis((long)(1000*seconds)));
    }
    static String bag(String input,long seed,double seconds) throws Exception {
        Scanner in=new Scanner(Path.of(input));in.useLocale(Locale.ROOT);
        Bag b=new Bag();int n=in.nextInt();b.capacity=in.nextInt();b.items=new ArrayList<>();
        for(int i=0;i<n;i++) b.items.add(new Item(i,in.nextInt(),in.nextInt()));in.close();
        long start=System.nanoTime();Solver<Bag> solver=SolverFactory.<Bag>create(config(Bag.class,Item.class,BagScore.class,seed,seconds)).buildSolver();
        double build=(System.nanoTime()-start)/1e9;start=System.nanoTime();Bag result=solver.solve(b);double elapsed=(System.nanoTime()-start)/1e9;
        return "values = "+result.items.stream().map(i->Boolean.TRUE.equals(i.selected)?1:0).toList()+"\nscore = \""+result.score+"\"\nsolve_call_seconds = "+elapsed+"\nbuild_seconds = "+build+"\n";
    }
    static String routing(String input,long seed,double seconds) throws Exception {
        Scanner in=new Scanner(Path.of(input));in.useLocale(Locale.ROOT);
        Routing p=new Routing();int n=in.nextInt();p.capacity=in.nextInt();p.visits=new ArrayList<>();p.routes=List.of(new Route());
        for(int i=0;i<n;i++) {
            Visit v=new Visit();v.id=in.nextInt();v.x=in.nextDouble();v.y=in.nextDouble();v.demand=in.nextInt();
            v.early=in.nextDouble();v.late=in.nextDouble();v.service=in.nextDouble();v.pickup=in.nextInt();
            if(i==0)p.depot=v;else p.visits.add(v);
        }
        in.close();long start=System.nanoTime();Solver<Routing> solver=SolverFactory.<Routing>create(config(Routing.class,Route.class,RouteScore.class,seed,seconds)).buildSolver();
        double build=(System.nanoTime()-start)/1e9;start=System.nanoTime();Routing result=solver.solve(p);double elapsed=(System.nanoTime()-start)/1e9;
        return "route = "+result.routes.getFirst().visits.stream().map(v->v.id).toList()+"\nscore = \""+result.score+"\"\nsolve_call_seconds = "+elapsed+"\nbuild_seconds = "+build+"\n";
    }
    public static void main(String[] args) throws Exception {
        // Warm-up gets a separate seed and no result is included in measurements.
        boolean route=args[0].equals("routing");
        if(route) routing(args[1],0,0.25); else bag(args[1],0,0.25);
        for(int seed=1;seed<=3;seed++) {
            String result=route?routing(args[1],seed,2.0):bag(args[1],seed,2.0);
            Files.writeString(Path.of(args[2],"timefold_native-"+seed+".toml"),result+"engine = \"timefold_native\"\nseed = "+seed+"\nbudget_seconds = 2.0\n");
            System.out.println("Timefold seed="+seed+" "+result.replace('\n',' '));
        }
    }
}
