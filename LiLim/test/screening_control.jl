using Test, TOML, SHA
include(joinpath(@__DIR__,"..","src","ScreeningControl.jl"))
const SC=ScreeningControl

@testset "Frozen stratified screening" begin
    bks=TOML.parsefile(joinpath(@__DIR__,"..","config","sintef-pdptw-bks-20261004.toml"))
    rows=SC.sample_instances(bks,20261009)
    @test rows==SC.sample_instances(bks,20261009)
    @test rows!=SC.sample_instances(bks,20261010)
    @test getindex.(rows,"size")==collect(SC.SIZES)
    @test allunique(getindex.(rows,"id"))
    for row in rows
        key=string(row["size"])*"."*row["id"]
        @test row["source_sha256"]==bks["instance_sha256"][key]
        @test row["target"]==bks["instances"][string(row["size"])][row["id"]]
    end
end

@testset "Two, one, zero and recovery" begin
    @test SC.resource_capacity(1.8,16*2.0^30)==2
    @test SC.resource_capacity(3.0,16*2.0^30)==1
    @test SC.resource_capacity(6.0,16*2.0^30)==0
    @test SC.resource_capacity(0.0,7*2.0^30)==0
    @test SC.resource_capacity(0.0,10*2.0^30)==1
    @test SC.resource_capacity(0.0,16*2.0^30)==2
    state=Dict("updated_epoch"=>100.0,"allowed_slots"=>[1,2],"reason"=>"running")
    @test SC.admission(state,1;now=101.0)
    @test !SC.admission(state,1;now=191.0)
    @test !SC.admission(state,3;now=101.0)
    state["reason"]="human_stop"
    @test !SC.admission(state,1;now=101.0)
    mktempdir() do dir
        SC.atomic(joinpath(dir,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>Int[],"reason"=>"resource_wait"))
        waiter=@async SC.await_permission(dir,2;interval=0.01)
        sleep(0.03);@test !istaskdone(waiter)
        SC.atomic(joinpath(dir,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>[2],"reason"=>"resource_wait"))
        @test fetch(waiter)["allowed_slots"]==[2]
        touch(joinpath(dir,"STOP_AFTER_TRIAL"))
        @test SC.await_permission(dir,2;interval=0.01)===nothing
        @test SC.halt_reason(dir)=="human_stop"
    end
end

@testset "GC stops need review, never resource recovery" begin
    record=Dict{String,Any}("method"=>"configuration","instance"=>"instance",
        "wall_seconds"=>60.0,"search_gc_seconds"=>6.0,"search_gc_fraction"=>0.10,
        "search_allocated_bytes"=>1024)
    @test SC.gc_alert(record,0.10)
    record["search_gc_fraction"]=0.09
    @test !SC.gc_alert(record,0.10)
    record["search_allocated_bytes"]=60*2.0^30
    @test SC.gc_alert(record,0.10)
    mktempdir() do dir
        SC.flag_gc(dir,1,"sealed-trial.toml",record,0.10)
        @test SC.halt_reason(dir)=="gc_review"
        SC.atomic(joinpath(dir,"state.toml"),Dict("updated_epoch"=>time(),"allowed_slots"=>[1,2],"reason"=>"running"))
        @test SC.await_permission(dir,1;interval=0.01)===nothing
        @test TOML.parsefile(joinpath(dir,"GC_ALERT_1.toml"))["method"]=="configuration"
    end
end

@testset "Failed children cannot disappear silently" begin
    if Sys.islinux()
        @test SC.cpu_counters().cpu_count>0
        @test SC.process_counters(getpid())!==nothing
        @test SC.available_memory()>0
        mktempdir() do dir
            jobs=[(;slot=1,output=joinpath(dir,"slot-1"))]
            @test SC.controller(dir,jobs,job->`sh -c 'exit 9'`;interval=0.01)=="process_failure"
            @test isfile(joinpath(dir,"PROCESS_FAILURE.toml"))
            @test TOML.parsefile(joinpath(dir,"state.toml"))["reason"]=="process_failure"
            @test !isdir(joinpath(dir,"controller.lock"))
        end
    end
end
