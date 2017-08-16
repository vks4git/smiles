module Data.SMARTS.Internal.Parser where

import           Data.Maybe                 (fromMaybe)
import           Data.SMARTS.Internal.Types
import           Data.SMILES.Atom           (Chirality (..))
import           Data.Text                  (pack)
import           Text.Megaparsec
import           Text.Megaparsec.Lexer
import           Text.Megaparsec.Text

smartsP :: Parser SMARTS
smartsP = do
  other <- many branchP
  return (SMARTS other)

-- *** Branch parser

branchP :: Parser Branch
branchP = compoundBranchP <|> (Linear <$> componentP)

compoundBranchP :: Parser Branch
compoundBranchP = between (char '(') (char ')') $ do
  unit <- componentP
  branch <- many branchP
  return (Compound unit branch)

-- *** Component parser

componentP :: Parser Component
componentP = Component <$> some (do
  bond <- bondExpressionP
  atom <- specificAtomP
  return (bond, atom))


-- *** Bond expressions parser

bondImplicitAndP :: Parser BondImplicitAnd
bondImplicitAndP = BondImplicitAnd <$> some bondP

bondExplicitAndP :: Parser BondExplicitAnd
bondExplicitAndP = do
  implAnd <- bondImplicitAndP `sepBy` char '&'
  let result = if null implAnd then [BondImplicitAnd [Single Pass]] else implAnd -- fixes cases when implicit single bond is not parsed
  return $ BondExplicitAnd result

bondOrP :: Parser BondOr
bondOrP = BondOr <$> bondExplicitAndP `sepBy` char ','

bondExpressionP :: Parser BondExpression
bondExpressionP = BondExpression <$> bondOrP `sepBy` char ';'

-- *** Bond parser

bondP :: Parser Bond
bondP = doubleP <|>
        tripleP <|>
        aromaticP <|>
        upDirectionP <|>
        downDirectionP <|>
        ringP <|>
        anyBondP <|>
        singleP

singleP :: Parser Bond
singleP = do
  neg <- negationP
  _ <- case neg of
    Pass -> try $ char '-'
    _    -> char '-'
  return (Single neg)

doubleP :: Parser Bond
doubleP = try $ do
  neg <- negationP
  _ <- char '='
  return (Double neg)

tripleP :: Parser Bond
tripleP = try $ do
  neg <- negationP
  _ <- char '#'
  return (Triple neg)

aromaticP :: Parser Bond
aromaticP = try $ do
  neg <- negationP
  _ <- char ':'
  return (Aromatic neg)

upDirectionP :: Parser Bond
upDirectionP = try $ do
  neg <- negationP
  _ <- char '/'
  pres <- presenceP
  return (Up neg pres)

downDirectionP :: Parser Bond
downDirectionP = try $ do
  neg <- negationP
  _ <- char '\\'
  pres <- presenceP
  return (Down neg pres)

ringP :: Parser Bond
ringP = try $ do
  neg <- negationP
  _ <- char '@'
  return (Ring neg)

anyBondP :: Parser Bond
anyBondP = try $ do
  neg <- negationP
  _ <- char '~'
  return (AnyBond neg)

-- *** Specific atom parser

specificAtomP :: Parser SpecificAtom
specificAtomP = (Primitive <$> primitiveAtomP <*> many cycleP) <|> descriptionP

descriptionP :: Parser SpecificAtom
descriptionP = do
  _ <- char '['
  expr <- atomExpressionP
  _ <- char ']'
  cycleIdx <- many cycleP
  return (Description expr cycleIdx)

-- *** Boolean expressions on Specifications

atomImplicitAndP :: Parser AtomImplicitAnd
atomImplicitAndP = AtomImplicitAnd <$> some specificationP

atomExplicitAndP :: Parser AtomExplicitAnd
atomExplicitAndP = AtomExplicitAnd <$> atomImplicitAndP `sepBy` char '&'

atomOrP :: Parser AtomOr
atomOrP = AtomOr <$> atomExplicitAndP `sepBy` char ','

atomExpressionP :: Parser AtomExpression
atomExpressionP = AtomExpression <$> atomOrP `sepBy` char ';'

-- *** Specification parser

specificationP :: Parser Specification
specificationP = explicitP <|>
                 degreeP <|>
                 attachedHP <|>
                 implicitHP <|>
                 ringMembershipP <|>
                 ringSizeP <|>
                 valenceP <|>
                 connectivityP <|>
                 ringConnectivityP <|>
                 negativeChargeP <|>
                 positiveChargeP <|>
                 atomicNumberP <|>
                 chiralityP <|>
                 atomicMassP <|>
                 recursiveP <|>
                 labelP

explicitP :: Parser Specification
explicitP = try $ do
  neg <- negationP
  atom <- atomSymbolP
  return (Explicit neg atom)

degreeP :: Parser Specification
degreeP = genericSpecP Degree 'D' 1

attachedHP :: Parser Specification
attachedHP = genericSpecP AttachedHydrogens 'H' 1

implicitHP :: Parser Specification
implicitHP = genericSpecP ImplicitHydrogens 'h' 1

ringMembershipP :: Parser Specification
ringMembershipP = genericSpecP RingMembership 'R' (-1)

ringSizeP :: Parser Specification
ringSizeP = genericSpecP RingSize 'r' (-1)

valenceP :: Parser Specification
valenceP = genericSpecP Valence 'v' 1

connectivityP :: Parser Specification
connectivityP = genericSpecP Connectivity 'X' 1

ringConnectivityP :: Parser Specification
ringConnectivityP = genericSpecP RingConnectivity 'r' (-1)

negativeChargeP :: Parser Specification
negativeChargeP = genericSpecP NegativeCharge '-' 1

positiveChargeP :: Parser Specification
positiveChargeP = genericSpecP PositiveCharge '+' 1

atomicNumberP :: Parser Specification
atomicNumberP = try $ do
  neg <- negationP
  _ <- char '#'
  num <- int
  return (AtomicNumber neg num)

chiralityP :: Parser Specification
chiralityP = try $ do
  neg <- negationP
  _ <- char '@'
  cw <- optional $ char '@'
  chClass <- optional (read <$> choice (string . show <$> [TH1 .. OH3]))
  presence <- presenceP
  case (cw, chClass, presence) of
    (Nothing, Nothing, pres)   -> return (CounterClockwise neg pres)
    (Just _, Nothing, Present) -> return (ClockwiseCh neg)
    (Nothing, Just ch, pres)   -> return (ChiralityClass neg ch pres)
    _                          -> fail "Error: no parse."

atomicMassP :: Parser Specification
atomicMassP = try $ do
  neg <- negationP
  num <- int
  return (AtomicMass neg num)

recursiveP :: Parser Specification
recursiveP = do
  neg <- negationP
  _ <- string "$("
  smarts <- smartsP
  _ <- char ')'
  return (Recursive neg smarts)

labelP :: Parser Specification
labelP = Class <$> (char ':' >> int)

genericSpecP :: (Negation -> Int -> Specification) -> Char -> Int -> Parser Specification
genericSpecP constructor sym def = try $ do
  neg <- negationP
  _ <- char sym
  num <- optional int
  return (constructor neg (fromMaybe def num))


-- *** Primitive atom parser

atomSymbolP :: Parser PrimitiveAtom
atomSymbolP = atomP <|> anyAtomP <|> anyAliphaticAtomP <|> anyAromaticAtomP

primitiveAtomP :: Parser PrimitiveAtom
primitiveAtomP = organicAtomP <|> anyAtomP <|> anyAliphaticAtomP <|> anyAromaticAtomP

anyAtomP :: Parser PrimitiveAtom
anyAtomP = char '*' >> return Any

anyAliphaticAtomP :: Parser PrimitiveAtom
anyAliphaticAtomP = char 'A' >> return AnyAliphatic

anyAromaticAtomP :: Parser PrimitiveAtom
anyAromaticAtomP = char 'a' >> return AnyAromatic

organicAtomP :: Parser PrimitiveAtom
organicAtomP = Atom . pack <$> choice (fmap string organicAtoms)

atomP :: Parser PrimitiveAtom
atomP = Atom . pack <$> choice (fmap string allAtoms)

-- *** Presence parser

presenceP :: Parser Presence
presenceP = do
  pres <- optional (char '?')
  case pres of
    Nothing -> return Present
    _       -> return Unspecified


-- *** Negation parser

negationP :: Parser Negation
negationP = do
  neg <- optional (char '!')
  case neg of
    Nothing -> return Pass
    _       -> return Negate

int :: Parser Int
int = fromIntegral <$> integer

cycleP :: Parser Int
cycleP = do
  dd <- optional (char '%')
  c1 <- digitChar
  case dd of
    Nothing -> return (read [c1])
    Just _  -> do
      c2 <- digitChar
      return (read [c1, c2])

allAtoms :: [String]
allAtoms =["Zr","Zn","Yb","Y","Xe","W","V","U","Tm","Tl",
           "Ti","Th","Te","Tc","Tb","Ta","Sr","Sn","Sm",
           "Si","Sg","Se","Sc","Sb","S","Ru","Rn","Rh",
           "Rg","Rf","Re","Rb","Ra","Pu","Pt","Pr","Po",
           "Pm","Pd","Pb","Pa","P","Os","O","Np","No","Ni",
           "Ne","Nd","Nb","Na","N","Mt","Mo","Mn","Mg",
           "Md","Lv","Lu","Lr","Li","La","Kr","K","Ir",
           "In","I","Hs","Ho","Hg","Hf","He","Ge",
           "Gd","Ga","Fr","Fm","Fl","Fe","F","Eu","Es",
           "Er","Dy","Ds","Db","Cu","Cs","Cr","Co","Cn",
           "Cm","Cl","Cf","Ce","Cd","Ca","C","Br","Bk",
           "Bi","Bh","Be","Ba","B","Au","At","As","Ar",
           "Am","Al","Ag","Ac","A","se","as","b", "c",
           "n", "o", "s", "p"]

organicAtoms :: [String]
organicAtoms = ["Br", "B", "Cl", "C", "N", "O", "S", "P",
                "F", "I", "b", "c", "n", "o", "s", "p"]
