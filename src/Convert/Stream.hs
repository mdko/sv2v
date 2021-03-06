{- sv2v
 - Author: Zachary Snow <zach@zachjs.com>
 -
 - Conversion of streaming concatenations.
 -}

module Convert.Stream (convert) where

import Convert.Traverse
import Language.SystemVerilog.AST

convert :: [AST] -> [AST]
convert = map $ traverseDescriptions convertDescription

convertDescription :: Description -> Description
convertDescription (description @ Part{}) =
    traverseModuleItems (traverseStmts traverseStmt) description
convertDescription other = other

streamerBlock :: Expr -> Expr -> (LHS -> Expr -> Stmt) -> LHS -> Expr -> Stmt
streamerBlock chunk size asgn output input =
    Block Seq ""
    [ Variable Local t inp [] $ Just input
    , Variable Local t out [] Nothing
    , Variable Local (IntegerAtom TInteger Unspecified) idx [] Nothing
    ]
    [ For inits cmp incr stmt
    , If NoCheck cmp2 stmt2 Null
    , asgn output (Ident out)
    ]
    where
        lo = Number "0"
        hi = BinOp Sub size (Number "1")
        t = IntegerVector TLogic Unspecified [(hi, lo)]
        name = streamerBlockName chunk size
        inp = name ++ "_inp"
        out = name ++ "_out"
        idx = name ++ "_idx"
        -- main chunk loop
        inits = Right [(LHSIdent idx, lo)]
        cmp = BinOp Lt (Ident idx) base
        incr = [(LHSIdent idx, AsgnOp Add, chunk)]
        lhs = LHSRange (LHSIdent out) IndexedMinus (BinOp Sub hi (Ident idx), chunk)
        expr = Range (Ident inp) IndexedPlus (Ident idx, chunk)
        stmt = Asgn AsgnOpEq Nothing lhs expr
        base = BinOp Mul (BinOp Div size chunk) chunk
        -- final chunk loop
        left = BinOp Sub size base
        lhs2 = LHSRange (LHSIdent out) IndexedMinus (BinOp Sub hi base, left)
        expr2 = Range (Ident inp) IndexedPlus (base, left)
        stmt2 = Asgn AsgnOpEq Nothing lhs2 expr2
        cmp2 = BinOp Gt left (Number "0")

streamerBlockName :: Expr -> Expr -> Identifier
streamerBlockName chunk size =
    "_sv2v_strm_" ++ shortHash (chunk, size)

traverseStmt :: Stmt -> Stmt
traverseStmt (Asgn op mt lhs expr) =
    traverseAsgn (lhs, expr) (Asgn op mt)
traverseStmt other = other

traverseAsgn :: (LHS, Expr) -> (LHS -> Expr -> Stmt) -> Stmt
traverseAsgn (lhs, Stream StreamR _ exprs) constructor =
    constructor lhs expr
    where
        expr = Concat $ exprs ++ [Repeat delta [Number "1'b0"]]
        size = DimsFn FnBits $ Right $ lhsToExpr lhs
        exprSize = DimsFn FnBits $ Right (Concat exprs)
        delta = BinOp Sub size exprSize
traverseAsgn (LHSStream StreamR _ lhss, expr) constructor =
    constructor (LHSConcat lhss) expr
traverseAsgn (lhs, Stream StreamL chunk exprs) constructor = do
    streamerBlock chunk size constructor lhs expr
    where
        expr = Concat $ Repeat delta [Number "1'b0"] : exprs
        size = DimsFn FnBits $ Right $ lhsToExpr lhs
        exprSize = DimsFn FnBits $ Right (Concat exprs)
        delta = BinOp Sub size exprSize
traverseAsgn (LHSStream StreamL chunk lhss, expr) constructor = do
    streamerBlock chunk size constructor lhs expr
    where
        lhs = LHSConcat lhss
        size = DimsFn FnBits $ Right expr
traverseAsgn (lhs, expr) constructor =
    constructor lhs expr
