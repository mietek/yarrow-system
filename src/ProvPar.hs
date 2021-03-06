-- File: ProvPar
-- Description: This module contains the parser for prover-commands,
--              including tactics

module ProvPar(parseTacticTerm,
               parseProverCommand,
               toLowerIdent,
               readNumDef1,
               parseOcc, parseOccs,
               parsePath   -- Just for testing
               ) where

import General
import HaMonSt

--import Basic
--import Paths
--import SyntaxI
--import ProvDat
import Engine

import Parser
import Scanner

---------------------------
--    P A R S I N G      --
---------------------------

-- context-free grammar for tactics:
-- TacticTerm = Tactic | Tactic Then TacticTerm
-- Tactic = Try Tactic |
--          Repeat Tactic |
--          (TacticTerm) |
--          "all ordinary tactics"

parseProverCommand :: Parse ProverCommand

-- the names of the tactics are no seperate tokens, so we have to parse them
-- as identifiers.
parseProverCommand =
  readToken' >>= \t0 ->
  let t = toLowerIdent t0 in
  case t of
  Ident "undo"    -> nextToken >>
                     fmap PUndo readNumDef1
  Ident "restart" -> nextToken >> return PRestart
  Ident "focus"   -> nextToken >>
                     eatNum >>= \n ->
                     return (PFocus n)
  otherwise       -> return PNoParse


parseTacticTerm :: Parse TacticTerm
parseTacticTerm = fmap (foldr1 TElse)
                      (parseList1 (separator Else) parseTacticFactor)

parseTacticFactor :: Parse TacticTerm
parseTacticFactor =
    parseTactic >>= \tac ->
    fmap (foldl TThen tac)
        (parseList commaOrThenL commaOrThenL parseTacticAltList)
                      where commaOrThenL = readToken' >>= \t ->
                                           if (t==Comma || t==Then) then
                                              nextToken >>
                                              return True
                                           else
                                              return False

parseTacticAltList :: Parse [TacticTerm]
parseTacticAltList =
                  readToken' >>= \t ->
                  if t == LeftP then
                     nextToken >>
                     parseList1 (separator Bar) parseTacticTerm >>= \tacList->
                     eat RightP "" >>
                     return tacList
                  else
                     parseTactic >>= \tac ->
                     return [tac]

parseTactic :: Parse TacticTerm
parseTactic =
  readToken >>= \(t0,lpi) ->
  let t = toLowerIdent t0 in
  case t of
  Ident "intro"      -> nextToken >>
                        startVar >>= \b ->
                        if b then
                           fmap TIntroVar parseVarList
                        else
                           return TIntro
  Ident "intros"     -> nextToken >>
                        readToken' >>= \t ->
                        case t of
                        Num n -> nextToken >> return (TIntrosNum n)
                        otherwise -> return TIntros
  Ident "assumption" -> nextToken >> return TAssumption
  Let                -> nextToken >>
                        parseDef >>= \((v,_),term,typ) ->
                        return (
                        if forgetIT typ == dummyTerm then
                           TLet v term
                        else
                           TLetW v term typ)
  Ident "simplify"   -> nextToken >> return TSimplify
  Ident "unfold"     -> nextToken >>
                        parseOccs >>= \o ->
                        parseVar >>= \v ->
                        readToken' >>= \t0' ->
                        let t' = toLowerIdent t0' in
                        case t' of
                        In -> nextToken >>
                              parseVar >>= \h ->
                              return (TUnfoldIn (o,v,h))
                        otherwise -> return (TUnfold (o,v))
  Ident "convert"    -> nextToken >> fmap TConvert parseTerm
  Ident "cut"        -> nextToken >> fmap TCut parseTerm
  Ident "first"      -> nextToken >> fmap TFirst parseTerm
  Ident "forward"    -> nextToken >>
                        fmap TForward parseExtTerm
  Ident "exact"      -> nextToken >> fmap TExact parseTerm
  Ident "apply"      -> nextToken >> fmap TApply parseExtTerm
  Ident "pattern"    -> nextToken >>
                        parseOccs >>= \o ->
                        parseTerm >>= \t ->
                        return (TPattern (o,t))
  Ident "rewrite"    -> nextToken >>
                        parseMaybeOcc >>= \o ->
                        parseExtTerm >>= \et ->
                        readToken' >>= \t0' ->
                        let t' = toLowerIdent t0' in
                        case t' of
                        In -> nextToken >>
                              parseVar >>= \h ->
                              return (TRewriteIn (o,et,h))
                        otherwise -> return (TRewrite (o,et))
  Ident "lewrite"    -> nextToken >>
                        parseMaybeOcc >>= \o ->
                        parseExtTerm >>= \et ->
                        readToken' >>= \t0' ->
                        let t' = toLowerIdent t0' in
                        case t' of
                        In -> nextToken >>
                              parseVar >>= \h ->
                              return (TLewriteIn (o,et,h))
                        otherwise -> return (TLewrite (o,et))
  Ident "refl"       -> nextToken >> return TRefl
  Ident "andi"       -> nextToken >> return TAndI
  Ident "andel"      -> nextToken >> fmap TAndEL parseExtTerm
  Ident "ander"      -> nextToken >> fmap TAndER parseExtTerm
  Ident "ande"       -> nextToken >> fmap TAndE parseExtTerm
  Ident "oril"       -> nextToken >> return TOrIL
  Ident "orir"       -> nextToken >> return TOrIR
  Ident "ore"        -> nextToken >> fmap TOrE parseExtTerm
  Ident "noti"       -> nextToken >> return TNotI
  Ident "note"       -> nextToken >> fmap TNotE parseExtTerm
  Ident "falsee"     -> nextToken >> return TFalseE
  Ident "existsi"    -> nextToken >> fmap TExistsI parseTerm
  Ident "existse"    -> nextToken >> fmap TExistsE parseExtTerm
  Ident "repeat"     -> nextToken >> fmap TRepeat parseTactic
  Ident "try"        -> nextToken >> fmap TTry parseTactic
  Ident "hide"       -> nextToken >>
                        fmap THide parseVarList
  Ident "unhide"     -> nextToken >>
                        startVar >>= \b ->
                        if b then
                           fmap TUnhide parseVarList
                        else
                           return TUnhideAll
  LeftP              -> nextToken >>
                        parseTacticTerm >>= \tac ->
                        eat RightP "" >>
                        return tac
  otherwise          -> pErr "Unknown command"

parseExtTerm :: Parse ExtTermIT
parseExtTerm = parseTerm >>= \t ->
               readToken' >>= \tok ->
               if tok == On then
                  nextToken >>
                  parseList1  (separator Comma) parseTerm >>= \ts ->
                  return (t,ts)
               else
                  return (t,[])

toLowerIdent :: Token -> Token
toLowerIdent (Ident s) = Ident (toLowers s)
toLowerIdent tok = tok

parseOccs :: Parse [Occurrence]
parseOccs = parseList startOcc (separator Comma) parseOcc

-- parseOcc parses one occurrence number
parseOcc :: Parse Occurrence
parseOcc = eatNum >>= \n ->
           if n==0 then
              fmap PathOccurrence (parseList startNum startNum eatNum)
           else
              return (NumOccurrence n)

startOcc = startNum

-- parseMaybeOcc parses at most one occurrence number (if none is given,
--          the result is 1)
parseMaybeOcc :: Parse Occurrence
parseMaybeOcc = startOcc >>= \b ->
                if b then
                   parseOcc
                else
                   return (NumOccurrence 1)


readNumDef1 :: Parse Int
readNumDef1 = readToken' >>= \t ->
              case t of
              Num n -> nextToken >> return n
              otherwise -> return 1


parseTermPath :: Parse TermPath
parseTermPath = parseList startNum startNum eatNum

parsePath :: Parse Path
parsePath = eatIdent "" >>= \id ->
            fmap (pair id) parseTermPath
