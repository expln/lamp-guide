open MM_context
open MM_parser
open MM_proof_verifier

type exprSource =
    | Hypothesis({label:string})
    | Assertion({args:array<int>, label:string})

type proofRecord = {
    expr:expr,
    proof:exprSource,
}

type proofTable = array<proofRecord>

let rightPad = (~content:string, ~char:string, ~totalLen:int):string => {
    let contentLen = content->Js_string2.length
    if (totalLen <= contentLen) {
        content
    } else {
        content ++ Js_string2.repeat(char, totalLen - contentLen)
    }
}

let exprSourceToStr = src => {
    switch src {
        | Hypothesis({label}) => label
        | Assertion({args, label}) => {
            if (args->Js.Array2.length == 0) {
                ": " ++ label
            } else {
                args->Js_array2.map(i=>i+1)->Js_array2.joinWith(",") ++ " : " ++ label
            }
        }
    }
}

let maxLength = (arr:array<string>):int => {
    arr->Js.Array2.map(Js_string2.length)->Js.Array2.reduce(Js_math.max_int, 0)
}

let proofTableToArrStr = (ctx:mmContext,tbl:proofTable):array<string> => {
    let srcs = tbl->Js_array2.map(r => r.proof->exprSourceToStr)
    let exprs = tbl->Js_array2.map(r => ctx->ctxIntsToStrExn(r.expr))

    let maxNumOfDigits = tbl->Js_array2.length->Belt.Int.toFloat->Js_math.log10->Js_math.floor_int + 1
    let col1Width = maxNumOfDigits + 1
    let col2Width = maxLength(srcs) + 1
    let col3Width = maxLength(exprs) + 1

    tbl->Js_array2.mapi((_,i) => {
        rightPad(~content=Belt_Int.toString(i+1), ~char=" ", ~totalLen=col1Width)
            ++ "| " ++ rightPad(~content=srcs[i], ~char=" ", ~totalLen=col2Width)
            ++ "| " ++ rightPad(~content=exprs[i], ~char=" ", ~totalLen=col3Width)
    })
}

let proofTableToStr = (ctx,tbl,title):string => {
    `--- TBL ${title} ---------------------------------------------------------------------------\n`
        ++ proofTableToArrStr(ctx,tbl)->Js_array2.joinWith("\n")
        ++ `\n--------------------------------------------------------------------------------------------`
}

let proofTablePrint = (ctx,tbl,title):unit => Js.Console.log(proofTableToStr(ctx,tbl,title))

let traverseRecordsInRpnOrder = (tbl,targetIdx,~onUse,~onReuse) => {
    let savedExprs = Belt_MutableSet.make(~id=module(ExprCmp))
    let reusedExprsSet = Belt_MutableSet.make(~id=module(ExprCmp))
    Expln_utils_data.traverseTree(
        (),
        tbl[targetIdx],
        (_, r) => {
            switch r.proof {
                | Hypothesis(_) => None
                | Assertion({args}) => if (savedExprs->Belt_MutableSet.has(r.expr)) { None } else { Some(args->Js_array2.map(a=>tbl[a])) }
            }
        },
        ~process = (_, r) => {
            switch r.proof {
                | Hypothesis(_) => onUse(r)
                | _ => ()
            }
            None
        },
        ~postProcess = (_, r) => {
            switch r.proof {
                | Assertion(_) => {
                    if (!(savedExprs->Belt_MutableSet.has(r.expr))) {
                        savedExprs->Belt_MutableSet.add(r.expr)
                        onUse(r)
                    } else {
                        let firstReusage = !(reusedExprsSet->Belt_MutableSet.has(r.expr))
                        if (firstReusage) {
                            reusedExprsSet->Belt_MutableSet.add(r.expr)
                        }
                        onReuse(r,firstReusage)
                    }
                }
                | _ => ()
            }
            None
        },
        ()
    )->ignore
}

let collectReusedExprs = (tbl,targetIdx):Belt_Set.t<expr, ExprCmp.identity> => {
    let reusedExprs = []
    traverseRecordsInRpnOrder(tbl,targetIdx,
        ~onUse = _ => (),
        ~onReuse = (r,firstReusage) => {
            if (firstReusage) {
                reusedExprs->Js_array2.push(r.expr)->ignore
            }
        }
    )
    Belt_Set.fromArray(reusedExprs, ~id=module(ExprCmp))
}

let createProof = (ctx:mmContext, tbl:proofTable, targetIdx:int):proof => {
    let tblLen = tbl->Js_array2.length
    if (tblLen <= targetIdx) {
        raise(MmException({msg:`tblLen <= targetIdx`}))
    }
    let mandHyps = getMandHyps(ctx, tbl[targetIdx].expr)
    let mandHypLabelToInt = Belt_MapString.fromArray(
        mandHyps->Js_array2.mapi(({label}, i) => (label, i+1))
    )
    let mandHypLen = mandHypLabelToInt->Belt_MapString.size
    let labels = []
    let labelToInt = label => {
        mandHypLen + switch labels->Js_array2.indexOf(label) {
            | -1 => labels->Js_array2.push(label)
            | i => i+1
        }
    }
    let reusedExprs = collectReusedExprs(tbl,targetIdx)
    let reusedExprToInt = Belt_MutableMap.make(~id=module(ExprCmp))
    let proofSteps = []
    traverseRecordsInRpnOrder(tbl,targetIdx,
        ~onUse = r => {
            let idx = switch r.proof {
                | Hypothesis({label}) => {
                    switch mandHypLabelToInt->Belt_MapString.get(label) {
                        | Some(i) => i
                        | None => labelToInt(label)
                    }
                }
                | Assertion({label}) => labelToInt(label)
            }
            proofSteps->Js_array2.push(idx)->ignore
            if (reusedExprs->Belt_Set.has(r.expr)) {
                proofSteps->Js_array2.push(0)->ignore
                reusedExprToInt->Belt_MutableMap.set(r.expr, reusedExprToInt->Belt_MutableMap.size + 1)
            }
        },
        ~onReuse = (r,_) => {
            proofSteps->Js_array2.push(-(reusedExprToInt->Belt_MutableMap.getExn(r.expr)))->ignore
        }
    )
    let labelsLastIdx = mandHypLen + labels->Js.Array2.length
    Compressed({
        labels,
        compressedProofBlock: proofSteps->Js_array2.map(i => {
            if (i == 0) {
                "Z"
            } else if (i < 0) {
                intToCompressedProofStr(labelsLastIdx - i)
            } else {
                intToCompressedProofStr(i)
            }
        })->Js_array2.joinWith("")
    })

}

let createProofTableFromProof: proofNode => proofTable  = proofNode => {
    let processedExprs = Belt_MutableSet.make(~id = module(ExprCmp))
    let exprToIdx = Belt_MutableMap.make(~id = module(ExprCmp))
    let tbl = []
    Expln_utils_data.traverseTree(
        (),
        proofNode,
        (_,n) => {
            switch n {
                | Hypothesis(_) => None
                | Calculated({args,expr}) => {
                    if (processedExprs->Belt_MutableSet.has(expr)) {
                        None
                    } else {
                        Some(args)
                    }
                }
            }
        },
        ~process = (_, n) => {
            switch n {
                | Hypothesis({hypLabel,expr}) => {
                    if (exprToIdx->Belt_MutableMap.get(expr)->Belt_Option.isNone) {
                        let idx = tbl->Js_array2.push({proof:Hypothesis({label:hypLabel}), expr})-1
                        exprToIdx->Belt_MutableMap.set(expr,idx)
                    }
                }
                | _ => ()
            }
            None
        },
        ~postProcess = (_, n) => {
            switch n {
                | Calculated({args,asrtLabel,expr}) => {
                    if (exprToIdx->Belt_MutableMap.get(expr)->Belt_Option.isNone) {
                        let idx = tbl->Js_array2.push({
                            proof:Assertion({
                                label:asrtLabel,
                                args: args->Js_array2.map(n => {
                                    let nExpr = getExprFromNode(n)
                                    exprToIdx->Belt_MutableMap.get(nExpr)->Belt_Option.getWithDefault(-1)
                                })
                            }),
                            expr
                        })-1
                        exprToIdx->Belt_MutableMap.set(expr,idx)
                    }
                }
                | _ => ()
            }
            None
        },
        ()
    )->ignore
    tbl
}