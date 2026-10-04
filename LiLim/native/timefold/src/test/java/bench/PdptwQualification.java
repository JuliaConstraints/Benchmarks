package bench;
import java.nio.file.*;
import java.util.*;

/** Exhaustive feasibility oracle and real FULL_ASSERT move/undo qualification. */
public final class PdptwQualification {
    static boolean feasible(Pdptw.Problem p) {
        boolean[] served=new boolean[p.visits.size()+1];int[] routeOf=new int[served.length],position=new int[served.length];
        for(Pdptw.Route route:p.routes) {
            int previous=1,load=0,pos=0;double clock=p.depot.early;
            for(Pdptw.Visit v:route.visits) {
                if(served[v.id-1])return false;served[v.id-1]=true;routeOf[v.id-1]=route.id;position[v.id-1]=++pos;
                clock=Math.max(v.early,clock+(previous==1?p.depot.service:p.visits.get(previous-2).service)+p.distances[previous-1][v.id-1]);
                if(clock>v.late+1e-8)return false;load+=v.demand;if(load<0 || load>p.capacity)return false;previous=v.id;
            }
            if(load!=0)return false;
            if(!route.visits.isEmpty() && clock+p.visits.get(previous-2).service+p.distances[previous-1][0]>p.depot.late+1e-8)return false;
        }
        for(Pdptw.Visit v:p.visits) {
            if(!served[v.id-1])return false;
            if(v.pickup>0 && (routeOf[v.id-1]!=routeOf[v.pickup-1] || position[v.id-1]<=position[v.pickup-1]))return false;
        }
        return true;
    }
    static int permutations(Pdptw.Problem p,List<Pdptw.Visit> visits,int index) {
        if(index<visits.size()) {
            int count=0;for(int j=index;j<visits.size();j++){Collections.swap(visits,index,j);count+=permutations(p,visits,index+1);Collections.swap(visits,index,j);}return count;
        }
        int count=0;
        for(int cut=0;cut<=visits.size();cut++) {
            p.routes.get(0).visits=new ArrayList<>(visits.subList(0,cut));p.routes.get(1).visits=new ArrayList<>(visits.subList(cut,visits.size()));
            var score=new Pdptw.FullScore().calculateScore(p);
            if(score.isFeasible()!=feasible(p))throw new AssertionError("Feasibility zero set");
            Pdptw.Incremental inc=new Pdptw.Incremental();inc.resetWorkingSolution(p);Pdptw.check(p,inc);
            var r=p.routes.get(0);
            inc.beforeListVariableChanged(r,"visits",0,cut);inc.beforeListVariableChanged(r,"visits",0,cut);
            inc.afterListVariableChanged(r,"visits",0,cut);inc.afterListVariableChanged(r,"visits",0,cut);Pdptw.check(p,inc);count++;
        }
        return count;
    }
    public static void main(String[] args) throws Exception {
        int checks=0;
        for(int capacity:new int[]{1,2})for(boolean tight:new boolean[]{false,true}) {
            Path input=Files.createTempFile("timefold-qualification-",".txt");
            try {
                String text="lilim-common-start/1 5 "+capacity+" 2\n1 0 0 0 0 20 0 0\n"+
                    "2 1 1 1 0 "+(tight?"1.5":"20")+" 0 0\n3 2 1 -1 0 "+(tight?"3":"20")+" 0 2\n"+
                    "4 -1 1 1 0 "+(tight?"1.5":"20")+" 0 0\n5 -2 1 -1 0 "+(tight?"3":"20")+" 0 4\n2 2 3\n2 4 5\n";
                Files.writeString(input,text);Pdptw.Problem p=Pdptw.read(input.toString());checks+=permutations(p,new ArrayList<>(p.visits),0);
                Pdptw.trial(input.toString(),"default",41,.2,1,true);
            } finally { Files.deleteIfExists(input); }
        }
        System.out.println("Qualified "+checks+" exhaustive route partitions and 4 native FULL_ASSERT searches.");
    }
}
