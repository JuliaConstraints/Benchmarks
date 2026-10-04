package bench;

import java.util.*;
import java.nio.file.*;
import java.time.Duration;
import java.math.BigDecimal;
import java.lang.management.ManagementFactory;
import java.util.concurrent.*;
import ai.timefold.solver.core.api.domain.entity.PlanningEntity;
import ai.timefold.solver.core.api.domain.common.PlanningId;
import ai.timefold.solver.core.api.domain.variable.PlanningListVariable;
import ai.timefold.solver.core.api.domain.valuerange.ValueRangeProvider;
import ai.timefold.solver.core.api.domain.solution.*;
import ai.timefold.solver.core.api.score.HardMediumSoftBigDecimalScore;
import ai.timefold.solver.core.api.score.calculator.*;
import ai.timefold.solver.core.api.solver.*;
import ai.timefold.solver.core.config.solver.*;
import ai.timefold.solver.core.config.score.director.ScoreDirectorFactoryConfig;
import ai.timefold.solver.core.config.localsearch.LocalSearchPhaseConfig;
import ai.timefold.solver.core.config.localsearch.decider.acceptor.LocalSearchAcceptorConfig;
import ai.timefold.solver.core.config.localsearch.decider.forager.LocalSearchForagerConfig;

/** Native lists, continuous double distances/times, route-level incremental scoring.
 * The Julia controller supplies a validated common start and audits every incumbent.
 */
public final class Pdptw {
    public static class Visit {
        @PlanningId public int id;
        public double x, y, early, late, service;
        public int demand, pickup;
        public Visit() {}
    }
    @PlanningEntity public static class Route {
        @PlanningId public int id;
        @PlanningListVariable public List<Visit> visits = new ArrayList<>();
        public Route() {}
    }
    @PlanningSolution public static class Problem {
        @PlanningEntityCollectionProperty public List<Route> routes;
        @ProblemFactCollectionProperty @ValueRangeProvider public List<Visit> visits;
        @ProblemFactProperty public Visit depot;
        @PlanningScore public HardMediumSoftBigDecimalScore score;
        public int capacity;
        public double[][] distances;
        public Problem() {}
    }
    private record Contribution(BigDecimal error, int used, BigDecimal distance) {}
    private static Contribution routeScore(Problem p, Route r, boolean[] seen) {
        Arrays.fill(seen, false);
        double error=0, distance=0, clock=p.depot.early;
        int load=0; Visit previous=p.depot;
        for (Visit v:r.visits) {
            double travel=p.distances[previous.id-1][v.id-1]; distance+=travel;
            clock=Math.max(v.early,clock+previous.service+travel);
            error+=Math.max(0,clock-v.late-1e-8);
            load+=v.demand; error+=Math.max(0,-load)+Math.max(0,load-p.capacity);
            // A delivery requires its pickup earlier in this same route.
            if(v.pickup>0 && !seen[v.pickup-1]) error+=1;
            seen[v.id-1]=true; previous=v;
        }
        if (!r.visits.isEmpty()) {
            double travel=p.distances[previous.id-1][0]; distance+=travel;
            error+=Math.max(0,clock+previous.service+travel-p.depot.late-1e-8)+Math.abs(load);
        }
        return new Contribution(BigDecimal.valueOf(error),r.visits.isEmpty()?0:1,BigDecimal.valueOf(distance));
    }
    /** Independent full calculation, used only for qualification and assertion mode. */
    public static class FullScore implements EasyScoreCalculator<Problem,HardMediumSoftBigDecimalScore> {
        public HardMediumSoftBigDecimalScore calculateScore(Problem p) {
            BigDecimal error=BigDecimal.ZERO,distance=BigDecimal.ZERO; int used=0;
            boolean[] seen=new boolean[p.visits.size()+1];
            for (Route r:p.routes) {
                Contribution c=routeScore(p,r,seen); error=error.add(c.error);distance=distance.add(c.distance);used+=c.used;
            }
            return score(error,used,distance);
        }
    }
    static HardMediumSoftBigDecimalScore score(BigDecimal error,int used,BigDecimal distance) {
        return HardMediumSoftBigDecimalScore.of(error.negate().stripTrailingZeros(),
            BigDecimal.valueOf(-used),distance.negate().stripTrailingZeros());
    }
    public static class Incremental implements IncrementalScoreCalculator<Problem,HardMediumSoftBigDecimalScore> {
        private Problem p;
        private Contribution[] cache;
        private boolean[] seen;
        private BigDecimal error,distance;
        private int used;
        public void resetWorkingSolution(Problem problem) {
            p=problem;cache=new Contribution[p.routes.size()];seen=new boolean[p.visits.size()+1];
            error=BigDecimal.ZERO;distance=BigDecimal.ZERO;used=0;
            for(Route r:p.routes) insert(r);
        }
        private void retract(Route r) {
            Contribution c=cache[r.id-1];
            // Undo notifications may contain repeated/overlapping ranges of
            // the same list. Retract its cached contribution only once.
            if(c==null) return;
            error=error.subtract(c.error);distance=distance.subtract(c.distance);used-=c.used;cache[r.id-1]=null;
        }
        private void insert(Route r) {
            // Replace, rather than add twice, after overlapping undo ranges.
            if(cache[r.id-1]!=null) retract(r);
            Contribution c=routeScore(p,r,seen);cache[r.id-1]=c;
            error=error.add(c.error);distance=distance.add(c.distance);used+=c.used;
        }
        public void beforeVariableChanged(Object entity,String name) { throw new UnsupportedOperationException(name); }
        public void afterVariableChanged(Object entity,String name) { throw new UnsupportedOperationException(name); }
        public void beforeListVariableChanged(Object entity,String name,int from,int to) { retract((Route)entity); }
        public void afterListVariableChanged(Object entity,String name,int from,int to) { insert((Route)entity); }
        public HardMediumSoftBigDecimalScore calculateScore() { return score(error,used,distance); }
    }
    static Problem read(String input) throws Exception {
        try(Scanner in=new Scanner(Path.of(input))) {
            in.useLocale(Locale.ROOT);
            if(!in.next().equals("lilim-common-start/1")) throw new IllegalArgumentException("Input schema");
            int n=in.nextInt(); Problem p=new Problem();p.capacity=in.nextInt();int fleet=in.nextInt();
            p.routes=new ArrayList<>();p.visits=new ArrayList<>();List<Visit> nodes=new ArrayList<>();
            for(int i=0;i<n;i++) {
                Visit v=new Visit();v.id=in.nextInt();v.x=in.nextDouble();v.y=in.nextDouble();v.demand=in.nextInt();
                v.early=in.nextDouble();v.late=in.nextDouble();v.service=in.nextDouble();v.pickup=in.nextInt();
                if(v.id!=i+1) throw new IllegalArgumentException("Node order");
                nodes.add(v);if(i==0)p.depot=v;else p.visits.add(v);
            }
            for(int i=1;i<=fleet;i++) {
                Route r=new Route();r.id=i;int length=in.nextInt();
                for(int j=0;j<length;j++)r.visits.add(nodes.get(in.nextInt()-1));p.routes.add(r);
            }
            if(in.hasNext())throw new IllegalArgumentException("Trailing input");
            p.distances=new double[n][n];
            for(int i=0;i<n;i++)for(int j=0;j<n;j++)p.distances[i][j]=Math.hypot(nodes.get(i).x-nodes.get(j).x,nodes.get(i).y-nodes.get(j).y);
            return p;
        }
    }
    static void check(Problem p,Incremental incremental) {
        if(!incremental.calculateScore().equals(new FullScore().calculateScore(p)))
            throw new IllegalStateException("Incremental/full score mismatch");
    }
    static int qualify(String input) throws Exception {
        Problem p=read(input);Incremental incremental=new Incremental();incremental.resetWorkingSolution(p);check(p,incremental);
        Random random=new Random(41);int checks=1;
        // Change/undo one or two complete planning lists, including infeasible routes.
        for(int i=0;i<2000;i++) {
            Route a=p.routes.get(random.nextInt(p.routes.size())),b=p.routes.get(random.nextInt(p.routes.size()));
            if(a.visits.isEmpty()) continue;
            List<Visit> aa=new ArrayList<>(a.visits),bb=new ArrayList<>(b.visits);
            incremental.beforeListVariableChanged(a,"visits",0,a.visits.size());
            if(a!=b)incremental.beforeListVariableChanged(b,"visits",0,b.visits.size());
            Visit v=a.visits.remove(random.nextInt(a.visits.size()));b.visits.add(random.nextInt(b.visits.size()+1),v);
            incremental.afterListVariableChanged(a,"visits",0,a.visits.size());
            if(a!=b)incremental.afterListVariableChanged(b,"visits",0,b.visits.size());check(p,incremental);checks++;
            incremental.beforeListVariableChanged(a,"visits",0,a.visits.size());
            if(a!=b)incremental.beforeListVariableChanged(b,"visits",0,b.visits.size());
            a.visits=aa;if(a!=b)b.visits=bb;
            incremental.afterListVariableChanged(a,"visits",0,a.visits.size());
            if(a!=b)incremental.afterListVariableChanged(b,"visits",0,b.visits.size());check(p,incremental);checks++;
        }
        return checks;
    }
    private record Lane(String text) {}
    static Lane solve(String input,String profile,long seed,double budget,long origin,int lane,boolean assertions) throws Exception {
        long cpuStart=ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime();long begin=System.nanoTime();
        Problem p=read(input);double remaining=budget-(System.nanoTime()-origin)/1e9;
        LocalSearchPhaseConfig phase=new LocalSearchPhaseConfig();
        if(profile.equals("late_acceptance_400"))phase.withAcceptorConfig(new LocalSearchAcceptorConfig().withLateAcceptanceSize(400))
            .withForagerConfig(new LocalSearchForagerConfig().withAcceptedCountLimit(1));
        else if(!profile.equals("default"))throw new IllegalArgumentException("Unknown profile");
        SolverConfig config=new SolverConfig().withSolutionClass(Problem.class).withEntityClasses(Route.class)
            .withRandomSeed(seed).withPhases(phase)
            .withEnvironmentMode(assertions?EnvironmentMode.FULL_ASSERT:EnvironmentMode.NO_ASSERT)
            .withScoreDirectorFactory(new ScoreDirectorFactoryConfig().withIncrementalScoreCalculatorClass(Incremental.class));
        if(assertions)config.getScoreDirectorFactoryConfig().withAssertionScoreDirectorFactory(
            new ScoreDirectorFactoryConfig().withEasyScoreCalculatorClass(FullScore.class));
        config.withTerminationSpentLimit(Duration.ofMillis(Math.max(1,(long)(remaining*1000))));
        Solver<Problem> solver=SolverFactory.<Problem>create(config).buildSolver();
        List<String> events=new ArrayList<>();
        solver.addEventListener(event->{
            double elapsed=(System.nanoTime()-origin)/1e9;
            if(elapsed>budget || !event.isNewBestSolutionInitialized() || !event.getNewBestScore().isFeasible())return;
            Problem best=event.getNewBestSolution();
            if(!best.score.equals(new FullScore().calculateScore(best)))throw new IllegalStateException("Incumbent score mismatch");
            List<List<Integer>> routes=new ArrayList<>();
            for(Route r:best.routes)if(!r.visits.isEmpty())routes.add(r.visits.stream().map(v->v.id).toList());
            events.add("\n[[trials.workers.trajectory]]\nseconds = "+((System.nanoTime()-origin)/1e9)+
                "\nvehicles = "+(-best.score.mediumScore().intValueExact())+"\ndistance = "+(-best.score.softScore().doubleValue())+
                "\nroutes = "+routes+"\n");
        });
        double build=(System.nanoTime()-begin)/1e9;remaining=budget-(System.nanoTime()-origin)/1e9;
        if(remaining>0) solver.solve(p);
        double elapsed=(System.nanoTime()-origin)/1e9,cpu=(ManagementFactory.getThreadMXBean().getCurrentThreadCpuTime()-cpuStart)/1e9;
        return new Lane("\n[[trials.workers]]\nworker = "+lane+"\nseed = "+seed+"\nthread_id = "+Thread.currentThread().threadId()+
            "\nbuild_seconds = "+build+"\nfinished_seconds = "+elapsed+"\nthread_cpu_seconds = "+cpu+
            (events.isEmpty()?"\ntrajectory = []\n":String.join("",events)));
    }
    static String trial(String input,String profile,long seed,double budget,int width,boolean assertions) throws Exception {
        ExecutorService pool=Executors.newFixedThreadPool(width);
        long origin=System.nanoTime();List<Future<Lane>> futures=new ArrayList<>();
        var os=(com.sun.management.OperatingSystemMXBean)ManagementFactory.getOperatingSystemMXBean();
        long processCpu=os.getProcessCpuTime();
        try {
            for(int i=1;i<=width;i++) { final int lane=i;futures.add(pool.submit(()->solve(input,profile,seed+10000*(lane-1),budget,origin,lane,assertions))); }
            List<Lane> lanes=new ArrayList<>();for(Future<Lane> f:futures)lanes.add(f.get());
            String result="\n[[trials]]\nseed = "+seed+"\nbudget_seconds = "+budget+"\nwall_seconds = "+((System.nanoTime()-origin)/1e9)+
                "\nprocess_cpu_seconds = "+((os.getProcessCpuTime()-processCpu)/1e9)+"\n";
            for(Lane lane:lanes)result+=lane.text;return result;
        } finally { pool.shutdownNow();if(!pool.awaitTermination(30,TimeUnit.SECONDS))throw new IllegalStateException("Workers failed to stop"); }
    }
    public static void main(String[] args) throws Exception {
        String input=args[0],profile=args[1];double budget=Double.parseDouble(args[2]);int width=Integer.parseInt(args[3]);
        Path out=Path.of(args[5]);if(Files.exists(out))throw new IllegalArgumentException("Output exists");
        boolean assertions=args.length>6 && args[6].equals("assert");
        int checks=qualify(input);
        // Warm the actual shape and every lane. Keep startup costs visible and separate.
        long warmStart=System.nanoTime();trial(input,profile,0,1.0,width,assertions);trial(input,profile,1,1.0,width,assertions);
        String result="schema = \"li-lim-timefold-native/1\"\nengine = \"timefold\"\nversion = \"2.6.0\"\nedition = \"Community\"\njava = \""+System.getProperty("java.version")+
            "\"\nprofile = \""+profile+"\"\nworkers = "+width+"\nnative_move_threads = 0\n"+
            "parallel_mode = \"independent serial solvers in one JVM, common wall deadline, final merge\"\n"+
            "scorer = \"route-level incremental; affected routes recomputed, full oracle checked at incumbents\"\n"+
            "qualification_checks = "+checks+"\nassertions = "+assertions+"\nwarmup_seconds = "+((System.nanoTime()-warmStart)/1e9)+"\n";
        for(String seed:args[4].split(","))result+=trial(input,profile,Long.parseLong(seed),budget,width,assertions);
        Files.writeString(out,result,StandardOpenOption.CREATE_NEW);
    }
}
