using Dates
include("../test/runtests.jl")
include("../src/ORTools.jl")
include("../src/Hexaly.jl")
include("../src/Selections.jl")
using .ReproductionORTools,.ReproductionHexaly,.ReproductionSelections
const ROOT=normpath(joinpath(@__DIR__,"../.."))
states=Dict{String,Any}("core"=>Dict("status"=>"passed","families"=>collect(string.(FAMILY_IDS)),"policies"=>POLICIES))
@testset "Actual OR-Tools CP-SAT models and original validators" begin
    ready=try
        ReproductionORTools.NativeSolvers.resolve_ortools(ReproductionORTools.NativeSolvers.default_python(ROOT);root=ROOT)
    catch e
        e isa ReproductionORTools.NativeSolvers.UnavailableSolver || rethrow()
        states["ortools"]=Dict("status"=>"skipped","reason"=>e.reason);nothing
    end
    if ready===nothing;@test_skip false
    else
        qualified=String[]
        for f in (:bpp,:bppc,:vbp,:salbp,:rcpsp,:jssp,:fjsp,:aircraft_landing)
            p=CASES[f];r=Base.invokelatest(solve_ortools,p;seconds=1.)
            @test !isempty(r["values"]) && validate(p,r["values"]).valid
            optimum=minimum(validate(p,collect(x)).objective[1] for x in Iterators.product(domains(p)...) if validate(p,collect(x)).valid)
            @test validate(p,r["values"]).objective[1]≈optimum
            @test r["bound"]<=optimum+1e-6
            push!(qualified,string(f))
        end
        states["ortools"]=Dict("status"=>"passed","version"=>ready["ortools_version"],"qualified_families"=>qualified,
            "scope"=>"small_exact_integer_original_validator_qualification_not_performance")
    end
end
@testset "GHOST Julia wrapper callback qualification" begin
    ready=try
        ReproductionORTools.NativeSolvers.resolve_ghost(;root=ROOT)
    catch e
        e isa ReproductionORTools.NativeSolvers.UnavailableSolver || rethrow()
        states["ghost"]=Dict("status"=>"skipped","reason"=>e.reason);nothing
    end
    if ready===nothing;@test_skip false
    else
        p=CASES[:bpp]
        for kind in (:direct,:icn_fused)
            r=Base.invokelatest(solve_ghost,p;seconds=.05,kind)
            @test !isempty(r.values) && validate(p,r.values).valid
        end
        states["ghost"]=Dict("status"=>"passed","qualified_families"=>["bpp"],"scope"=>"Julia_wrapper_BPP_direct_and_ICN_callbacks_only","threads"=>1)
    end
end
@testset "Original source-format samples and native Hexaly gate" begin
    manifest=selection(joinpath(ROOT,"Hexaly/config/instances.toml"))
    bank=prepare_backend(:icn_fused);qualified=String[]
    for row in manifest["instances"]
        if !isfile(joinpath(ROOT,row["path"]));@test_skip false;continue;end
        loaded=load_instance(ROOT,row);p=loaded.p;x=initial(p)
        @test all(i->x[i] in domains(p)[i],eachindex(x))
        @test iszero(Base.invokelatest(error_value,bank,p,x))==validate(p,x).valid
        push!(qualified,row["id"])
        if p.family in keys(TEMPLATES)
            source=template_model(ROOT,p)
            @test occursin("JC_DECISIONS_1",source)
        end
    end
    states["original_samples"]=Dict("status"=>"passed","instances"=>qualified,"scope"=>"format_and_error_zero_set_not_complete_published_corpus")
    executable=try
        ReproductionHexaly.NativeSolvers.resolve_hexaly(get(ENV,"HEXALY_EXECUTABLE","hexaly"))
    catch e
        e isa ReproductionHexaly.NativeSolvers.UnavailableSolver || rethrow()
        states["hexaly"]=Dict("status"=>"skipped","reason"=>e.reason);nothing
    end
    if executable===nothing;@test_skip false
    else
        row=only(filter(r->r["family"]=="bpp",manifest["instances"]));loaded=load_instance(ROOT,row)
        r=solve_hexaly(ROOT,loaded.p,loaded.path;seconds=1.,executable)
        @test r["status"]=="feasible" && validate(loaded.p,r["values"]).valid
        states["hexaly"]=Dict("status"=>"passed","version"=>"15.0","qualified_families"=>["bpp"],
            "scope"=>"Actual_vendor_BPP_model_and_original_validator_only_other_models_require_native_qualification")
    end
end
@testset "ROADEF-2020 official example objective" begin
    path=joinpath(ROOT,"Hexaly/data/maintenance_example/example1.json")
    if !isfile(path);@test_skip false
    else
        p=read_problem(path;family=:maintenance)
        @test validate(p,[1,1,2]).valid
        @test validate(p,[1,1,2]).objective[1]≈4.5
    end
end
include("../test/campaign.jl")
report=Dict("schema"=>"discrete-original-qualification/1","checked_at_utc"=>string(now(UTC)),"status"=>"passed","checks"=>states)
for arg in ARGS
    startswith(arg,"--output=") || error("Unknown qualification option")
    path=abspath(arg[10:end]);ispath(path) && error("Qualification evidence already exists")
    mkpath(dirname(path))
    mktemp(dirname(path)) do temporary,io
        TOML.print(io,report;sorted=true);close(io);mv(temporary,path)
    end
end
