/**
 * Every written block built, formatted, linted and tested alone, `mise run blocks`. One in work
 * that fails is listed in red and fails nothing, `model/plan/work.res`.
 */
let packages = switch Base.args->Array.indexOf("--blocks") {
| -1 => []
| index => Base.args->Array.get(index + 1)->Option.getOr("")->String.split(",")
}
Tree.built(Blocks.own(), ~packages)
