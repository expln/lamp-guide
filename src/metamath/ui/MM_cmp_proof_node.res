open Expln_React_common
open MM_proof_tree_dto
open MM_context
open MM_unification_debug

type state = {
    expanded: bool,
    expandedSrcs: array<int>,
}

let makeInitialState = ():state => {
    {
        expanded: false,
        expandedSrcs: [],
    }
}

let toggleExpanded = st => {
    {
        ...st,
        expanded: !st.expanded
    }
}

let isExpandedSrc = (st,srcIdx) => st.expandedSrcs->Js_array2.includes(srcIdx)

let expandCollapseSrc = (st,srcIdx) => {
    if (st.expandedSrcs->Js_array2.includes(srcIdx)) {
        {
            ...st,
            expandedSrcs: st.expandedSrcs->Js.Array2.filter(i => i != srcIdx)
        }
    } else {
        {
            ...st,
            expandedSrcs: st.expandedSrcs->Js.Array2.concat([srcIdx])
        }
    }
}

let validProofIcon = 
    <span
        title="This is a valid proof"
        style=ReactDOM.Style.make(~color="green", ~fontWeight="bold", ())
    >
        {React.string("\u2713")}
    </span>

module rec ProofNodeDtoCmp: {
    @react.component
    let make: (
        ~tree: proofTreeDto,
        ~nodeIdx: int,
        ~isRootStmt: int=>bool,
        ~nodeIdxToLabel: int=>string,
        ~exprToStr: expr=>string,
        ~exprToReElem: expr=>reElem,
    ) => reElem
} = {
    @react.component
    let make = (
        ~tree: proofTreeDto,
        ~nodeIdx: int,
        ~isRootStmt: int=>bool,
        ~nodeIdxToLabel: int=>string,
        ~exprToStr: expr=>string,
        ~exprToReElem: expr=>reElem,
    ) => {
        let (state, setState) = React.useState(makeInitialState)

        let node = tree.nodes[nodeIdx]

        let getParents = () => {
            if (node.parents->Js.Array2.length == 0) {
                switch node.proof {
                    | None => []
                    | Some(src) => [src]
                }
            } else {
                node.parents
            }
        }

        let parents = getParents()

        let actToggleExpanded = () => {
            setState(toggleExpanded)
        }

        let actToggleSrcExpanded = (srcIdx) => {
            setState(expandCollapseSrc(_, srcIdx))
        }

        let getColorForLabel = nodeIdx => {
            if(isRootStmt(nodeIdx)) {
                "black"
            } else {
                "lightgrey"
            }
        }

        let rndExpandCollapseIcon = (expand) => {
            let char = if (expand) {"\u229E"} else {"\u229F"}
            <span style=ReactDOM.Style.make(~fontSize="13px", ())>
                {React.string(char)}
            </span>
        }

        let rndCollapsedArgs = (args, srcIdx) => {
            <span
                onClick={_=>actToggleSrcExpanded(srcIdx)}
                style=ReactDOM.Style.make(~cursor="pointer", ())
            >
                {React.string("( ")}
                {
                    args->Js_array2.mapi((arg,i) => {
                        <span
                            key={i->Belt_Int.toString} 
                            style=ReactDOM.Style.make(~color=getColorForLabel(arg), ())
                        >
                            {React.string(nodeIdxToLabel(arg) ++ " ")}
                        </span>
                    })->React.array
                }
                {React.string(" )")}
            </span>
        }

        let rndErr = err => {
            <pre style=ReactDOM.Style.make(~color="red", ~margin="0px", ())>
            {
                switch err {
                    | UnifErr => React.string("Details of the error were not stored.")
                    | DisjCommonVar({frmVar1, expr1, frmVar2, expr2, commonVar}) => {
                        let arrow = Js_string2.fromCharCode(8594)
                        React.string(
                            `Unsatisfied disjoint, common variable ${exprToStr([commonVar])}:\n`
                                ++ `${exprToStr([frmVar1])} ${arrow} ${exprToStr(expr1)}\n`
                                ++ `${exprToStr([frmVar2])} ${arrow} ${exprToStr(expr2)}`
                        )
                    }
                    | Disj({frmVar1, expr1, var1, frmVar2, expr2, var2}) => {
                        let arrow = Js_string2.fromCharCode(8594)
                        React.string(
                            `Missing disjoint ${exprToStr([var1])},${exprToStr([var2])}:\n`
                                ++ `${exprToStr([frmVar1])} ${arrow} ${exprToStr(expr1)}\n`
                                ++ `${exprToStr([frmVar2])} ${arrow} ${exprToStr(expr2)}`
                        )
                    }
                    | UnprovedFloating({expr:expr}) => 
                        React.string( `Could not prove this floating statement:\n` ++ exprToStr(expr) )
                }
            }
            </pre>
        }

        let rndExpandedArgs = (args, srcIdx) => {
            <table>
                <tbody>
                    <tr key="c-args">
                        <td>
                            {rndCollapsedArgs(args, srcIdx)}
                        </td>
                    </tr>
                    {
                        switch parents[srcIdx] {
                            | AssertionWithErr({err}) => {
                                <tr>
                                    <td> {rndErr(err)} </td>
                                </tr>
                            }
                            | _ => React.null
                        }
                    }
                    {
                        if (args->Js_array2.length == 0) {
                            <tr key={"-exp"}>
                                <td>
                                    {React.string("This assertion doesn't have hypotheses.")}
                                </td>
                            </tr>
                        } else {
                            args->Js_array2.mapi((arg,argIdx) => {
                                <tr key={argIdx->Belt_Int.toString ++ "-exp"}>
                                    <td>
                                        <ProofNodeDtoCmp
                                            tree
                                            nodeIdx=arg
                                            isRootStmt
                                            nodeIdxToLabel
                                            exprToStr
                                            exprToReElem
                                        />
                                    </td>
                                </tr>
                            })->React.array
                        }
                    }
                </tbody>
            </table>
        }

        let rndStatusIconForStmt = (node:proofNodeDto) => {
            <span
                title="This is proved"
                style=ReactDOM.Style.make(
                    ~color="green", 
                    ~fontWeight="bold", 
                    ~visibility=if (node.proof->Belt_Option.isSome) {"visible"} else {"hidden"},
                    ()
                )
            >
                {React.string("\u2713")}
            </span>
        }

        let rndStatusIconForSrc = (src:exprSrcDto) => {
            switch src {
                | VarType | Hypothesis(_) => validProofIcon
                | Assertion({args}) => {
                    let allArgsAreProved = args->Js_array2.every(arg => tree.nodes[arg].proof->Belt_Option.isSome)
                    if (allArgsAreProved) {
                        validProofIcon
                    } else {
                        React.null
                    }
                }
                | AssertionWithErr({err}) => {
                    <span
                        title="Click to see error details"
                        style=ReactDOM.Style.make(~color="red", ~fontWeight="bold", ~cursor="pointer", ())
                    >
                        {React.string("\u2717")}
                    </span>
                }
            }
        }

        let rndSrc = (src,srcIdx) => {
            let key = srcIdx->Belt_Int.toString
            switch src {
                | VarType => {
                    <tr key>
                        <td style=ReactDOM.Style.make(~verticalAlign="top", ())> {rndStatusIconForSrc(src)} </td>
                        <td> {React.string("VarType")} </td>
                        <td> {React.null} </td>
                    </tr>
                }
                | Hypothesis({label}) => {
                    <tr key>
                        <td style=ReactDOM.Style.make(~verticalAlign="top", ())> {rndStatusIconForSrc(src)} </td>
                        <td> {React.string("Hyp " ++ label)} </td>
                        <td> {React.null} </td>
                    </tr>
                }
                | Assertion({args, label}) | AssertionWithErr({args, label}) => {
                    <tr key>
                        <td style=ReactDOM.Style.make(~verticalAlign="top", ())> {rndStatusIconForSrc(src)} </td>
                        <td
                            onClick={_=>actToggleSrcExpanded(srcIdx)}
                            style=ReactDOM.Style.make(~cursor="pointer", ~verticalAlign="top", ())
                        >
                            {rndExpandCollapseIcon(!(state->isExpandedSrc(srcIdx)))}
                            <i>{React.string(label)}</i>
                        </td>
                        <td>
                            {
                                if (state->isExpandedSrc(srcIdx)) {
                                    rndExpandedArgs(args, srcIdx)
                                } else {
                                    rndCollapsedArgs(args, srcIdx)
                                }
                            } 
                        </td>
                    </tr>
                }
            }
        }

        let rndSrcs = () => {
            if (parents->Js.Array2.length == 0) {
                React.string("Sources are not set.")
            } else {
                <table>
                    <tbody>
                        {
                            parents->Js_array2.mapi((src,srcIdx) => rndSrc(src,srcIdx))->React.array
                        }
                    </tbody>
                </table>
            }
        }

        let rndNode = () => {
            <table>
                <tbody>
                    <tr>
                        <td> {rndStatusIconForStmt(node)} </td>
                        <td
                            style=ReactDOM.Style.make(
                                ~cursor="pointer", 
                                ~color=getColorForLabel(nodeIdx), ()
                            )
                            onClick={_=>actToggleExpanded()}
                        > 
                            {rndExpandCollapseIcon(!state.expanded)}
                            {React.string(nodeIdxToLabel(nodeIdx) ++ ":")}
                        </td>
                        <td
                            style=ReactDOM.Style.make( ~cursor="pointer", ())
                            onClick={_=>actToggleExpanded()}
                        > 
                            {exprToReElem(tree.nodes[nodeIdx].expr)} 
                        </td>
                    </tr>
                    {
                        if (state.expanded) {
                            <tr>
                                <td> React.null </td>
                                <td> React.null </td>
                                <td>
                                    {rndSrcs()}
                                </td>
                            </tr>
                        } else {
                            React.null
                        }
                    }
                </tbody>
            </table>
        }

        rndNode()
    }
}

@react.component
let make = (
    ~tree: proofTreeDto,
    ~nodeIdx: int,
    ~isRootStmt: int=>bool,
    ~nodeIdxToLabel: int=>string,
    ~exprToStr: expr=>string,
    ~exprToReElem: expr=>reElem,
) => {
    <ProofNodeDtoCmp
        tree
        nodeIdx
        isRootStmt
        nodeIdxToLabel
        exprToStr
        exprToReElem
    />
}