open MM_context

type jstf = {
    args: array<string>,
    label: string
}

type stmtDto = {
    label:string,
    expr:expr,
    exprStr:string,
    jstf:option<jstf>,
    isProved: bool,
}

type stmtsDto = {
    newVars: array<int>,
    newVarTypes: array<int>,
    newDisj:disjMutable,
    newDisjStr:array<string>,
    stmts: array<stmtDto>,
}
    