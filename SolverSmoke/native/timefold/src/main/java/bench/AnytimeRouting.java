package bench;

import java.util.*;
import java.nio.file.*;
import java.math.BigDecimal;
import ai.timefold.solver.core.api.domain.entity.PlanningEntity;
import ai.timefold.solver.core.api.domain.common.PlanningId;
import ai.timefold.solver.core.api.domain.variable.PlanningListVariable;
import ai.timefold.solver.core.api.domain.valuerange.ValueRangeProvider;
import ai.timefold.solver.core.api.domain.solution.*;
import ai.timefold.solver.core.api.score.HardMediumSoftBigDecimalScore;
import ai.timefold.solver.core.api.score.calculator.EasyScoreCalculator;
import ai.timefold.solver.core.api.solver.*;
import ai.timefold.solver.core.config.solver.SolverConfig;
import ai.timefold.solver.core.config.constructionheuristic.ConstructionHeuristicPhaseConfig;
import ai.timefold.solver.core.config.localsearch.LocalSearchPhaseConfig;
import ai.timefold.solver.core.config.localsearch.decider.acceptor.LocalSearchAcceptorConfig;
import ai.timefold.solver.core.config.localsearch.decider.forager.LocalSearchForagerConfig;

/** Full fleet, native planning lists; experiment scheduling and validation are Julia. */
public class AnytimeRouting {
    @PlanningEntity public static class Route {
        @PlanningId public int id;
        @PlanningListVariable public List<Smoke.Visit> visits=new ArrayList<>();
        public Route() {}
    }
    @PlanningSolution public static class Problem {
        @PlanningEntityCollectionProperty public List<Route> routes;
        @ProblemFactCollectionProperty @ValueRangeProvider public List<Smoke.Visit> visits;
        @ProblemFactProperty public Smoke.Visit depot;
        @PlanningScore public HardMediumSoftBigDecimalScore score;
        public int capacity;
        public double bigM;
        public double[][] distances;
        public Problem() {}
    }
    public static class Scorer implements EasyScoreCalculator<Problem,HardMediumSoftBigDecimalScore> {
        public HardMediumSoftBigDecimalScore calculateScore(Problem p) {
            double error=0,distance=0;int used=0;
            for(Route r:p.routes) {
                if(r.visits.isEmpty())continue;
                used++;Smoke.Visit previous=p.depot;double time=p.depot.early;int load=0;
                Set<Integer> seen=new HashSet<>();
                for(Smoke.Visit v:r.visits) {
                    double travel=p.distances[previous.id-1][v.id-1];distance+=travel;
                    time=Math.max(v.early,time+previous.service+travel);error+=Math.max(0,time-v.late);
                    load+=v.demand;error+=Math.max(0,-load)+Math.max(0,load-p.capacity);
                    if(v.pickup>0 && !seen.contains(v.pickup))error+=1;
                    seen.add(v.id);previous=v;
                }
                double travel=p.distances[previous.id-1][0];distance+=travel;
                error+=Math.max(0,time+previous.service+travel-p.depot.late)+Math.abs(load);
            }
            return HardMediumSoftBigDecimalScore.of(BigDecimal.valueOf(-error),BigDecimal.valueOf(-used),BigDecimal.valueOf(-distance));
        }
    }
    static Problem read(String input) throws Exception {
        Scanner in=new Scanner(Path.of(input));in.useLocale(Locale.ROOT);
        if(!in.next().equals("pdptw/1"))throw new IllegalArgumentException("Invalid input version");
        Problem p=new Problem();int n=in.nextInt();p.capacity=in.nextInt();int fleet=in.nextInt();
        p.routes=new ArrayList<>();p.visits=new ArrayList<>();
        for(int i=1;i<=fleet;i++){Route r=new Route();r.id=i;p.routes.add(r);}
        List<Smoke.Visit> nodes=new ArrayList<>();
        for(int i=0;i<n;i++) {
            Smoke.Visit v=new Smoke.Visit();v.id=in.nextInt();v.x=in.nextDouble();v.y=in.nextDouble();
            v.demand=in.nextInt();v.early=in.nextDouble();v.late=in.nextDouble();v.service=in.nextDouble();v.pickup=in.nextInt();
            nodes.add(v);if(i==0)p.depot=v;else p.visits.add(v);
        }
        in.close();p.distances=new double[n][n];double max=0;
        for(int i=0;i<n;i++)for(int j=0;j<n;j++) {
            p.distances[i][j]=Math.hypot(nodes.get(i).x-nodes.get(j).x,nodes.get(i).y-nodes.get(j).y);
            max=Math.max(max,p.distances[i][j]);
        }
        p.bigM=2*(n-1)*max+1;return p;
    }
    static String solve(String input,String profile,long seed,double seconds) throws Exception {
        long origin=System.nanoTime();Problem p=read(input);
        SolverConfig config=Smoke.config(Problem.class,Route.class,Scorer.class,seed,seconds);
        if(profile.equals("late_acceptance_400")) {
            config.withPhases(new ConstructionHeuristicPhaseConfig(),new LocalSearchPhaseConfig()
                .withAcceptorConfig(new LocalSearchAcceptorConfig().withLateAcceptanceSize(400))
                .withForagerConfig(new LocalSearchForagerConfig().withAcceptedCountLimit(1)));
        } else if(!profile.equals("default"))throw new IllegalArgumentException("Unknown profile");
        Solver<Problem> solver=SolverFactory.<Problem>create(config).buildSolver();
        List<String> events=new ArrayList<>();
        long solveOrigin=System.nanoTime();double build=(solveOrigin-origin)/1e9;
        solver.addEventListener(event->{
            if(!event.isNewBestSolutionInitialized() || !event.getNewBestScore().isFeasible())return;
            Problem best=event.getNewBestSolution();
            List<Integer> values=new ArrayList<>();int separator=best.visits.size()+2;
            for(int i=0;i<best.routes.size();i++) {
                for(Smoke.Visit v:best.routes.get(i).visits)values.add(v.id);
                if(i+1<best.routes.size())values.add(separator++);
            }
            double objective=-best.score.mediumScore().doubleValue()*p.bigM-best.score.softScore().doubleValue();
            double elapsed=(System.nanoTime()-origin)/1e9;
            events.add("\n[[events]]\nvalues = "+values+"\nobjective = "+objective+
                "\nelapsed_seconds = "+elapsed+"\nsolve_seconds = "+event.getTimeMillisSpent()/1000.0+
                "\nphase = \"search\"\n");
        });
        solver.solve(p);double elapsed=(System.nanoTime()-solveOrigin)/1e9;
        return "schema = \"incumbent-trace/1\"\nengine = \"timefold_native\"\nprofile = \""+profile+
            "\"\nclock = \"Timefold milliseconds and wrapper monotonic nanoseconds\"\ntiming_available = true\nproof_time_available = false\n"+
            "found = "+!events.isEmpty()+"\nseed = "+seed+"\nseed_controlled = true\nthreads = 1\ncpu_ceiling = 4\nwarmup_solves = 2\nwarmup_budget_seconds = 2.0\n"+
            "budget_seconds = "+seconds+"\nbuild_seconds = "+build+"\nsolve_call_seconds = "+elapsed+
            (events.isEmpty()?"\nevents = []\n":"\n"+String.join("",events));
    }
    public static void main(String[] args) throws Exception {
        for(int i=0;i<2;i++)solve(args[5],args[1],0,2.0);
        Files.writeString(Path.of(args[4]),solve(args[0],args[1],Long.parseLong(args[3]),Double.parseDouble(args[2])));
    }
}
