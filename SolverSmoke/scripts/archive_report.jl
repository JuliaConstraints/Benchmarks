include("activate.jl")
using TOML, SHA
attempt=abspath(ARGS[1])
isfile(joinpath(attempt,"completed.toml")) || error("Attempt is incomplete")
isfile(joinpath(attempt,"AUDIT.md")) && error("Audited development attempt cannot qualify the study")
records=TOML.parsefile(joinpath(attempt,"validation.toml"))["records"]
length(records)==33 && all(r->r["valid"],records) || error("Qualification requires all 33 valid incumbents")
for r in records
    raw=joinpath(attempt,r["family"],"$(r["engine"])-$(r["repetition"]).toml")
    bytes2hex(sha256(read(raw)))==r["raw_sha256"] || error("Raw evidence changed")
end
target=projectdir("QUALIFICATION.md")
cp(joinpath(attempt,"report.md"),target;force=true)
println("Archived qualified report: ",target)
function checksyntax(expression)
    expression isa Expr || return
    expression.head in (:error,:incomplete) && error("Julia syntax error: $expression")
    foreach(checksyntax,expression.args)
end
for folder in (scriptsdir(),srcdir()), (dir,_,files) in walkdir(folder),file in files
    endswith(file,".jl") || continue
    path=joinpath(dir,file);checksyntax(Meta.parseall(read(path,String);filename=path))
end
println("Julia script syntax checked.")
