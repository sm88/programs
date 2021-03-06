import Data.Char	--for isDigit
 --Polymorpic parser type
type Parser symbol result = [symbol] -> [([symbol],result)]

--parser parsing character a
symbola :: Parser Char Char
symbola [] = []
symbola (x:xs) 
  | x=='a' = [(xs,'a')]
  | otherwise = []

--parsing any symbol (single)
symbol :: Eq a => a -> Parser a a	--the symbol should be able to perform == operation
symbol _ [] = []
symbol a (x:xs)
  | x==a = [(xs,a)]
  | otherwise = []

--single symbol parser with list comprehension
symbol' :: Eq a => a -> Parser a a
symbol' _ [] = []
symbol' a (x:xs) = [(xs,a) | x==a]

--token parser
token :: Eq s => [s] -> Parser s [s]	--as now the result will also be a string
token _ [] = []
token text input
  | text==take n input = [(drop n input, text)]
  | otherwise = []
  where n=length text

--another generalization of symbol - satisfy -> returns tree based on some predicate (earlier we added class constraint Eq)
satisfy :: (s -> Bool) -> Parser s s
satisfy p [] = []
satisfy p (x:xs) = [(xs,x) | p x]	--no generator so when predicate is false, list is null

symbol'' :: Eq a => a -> Parser a a
symbol'' a list = satisfy (a==) list

--epsilon, (empty string)
epsilon :: Parser s ()
epsilon input = [(input,())]

--succeed, like epsilon but returns fixed value. Input is unprocessed
succeed :: a -> Parser s a
succeed fixed list = [(list,fixed)]

--epsilon in terms of satisfy
epsilon' :: Parser s ()
epsilon' input = succeed () input

--always fails, returns empty list
fail' :: Parser s r
fail' input = []

-------------------------------------------------------
--Parsers for Non-terminals----------------------------
-------------------------------------------------------
infixr 6 <*>
infixr 4 <|>
--sequential combinator
(<*>) :: Parser s a -> Parser s b -> Parser s (a,b)
(p1 <*> p2) xs = [(xs2,(v1,v2)) |(xs1,v1) <- p1 xs, (xs2,v2) <- p2 xs1]

--alternate composition
(<|>) :: Parser s a -> Parser s a -> Parser s a
(p1 <|> p2) xs = p1 xs ++ p2 xs		--just parses xs with p1 and p2 respectively and returns complete list
     
--remove extra space from input
sp :: Parser Char a -> Parser Char a
sp p = p.dropWhile (==' ')

--only keep elements with null rest string
just :: Parser s a -> Parser s a
just p = filter (null.fst).p

--applies some function to result of parser
infixr 5 <@
(<@) :: Parser s a -> (a->b) -> Parser s b
(p <@ f) xs = [(ys,f v) | (ys, v) <- p xs]

--char to integer, using symbol
digit :: Parser Char Int
digit = satisfy isDigit <@ (\x -> ord x - ord '0')

--deterministic parser, will return result of first tuple with empty rest string 
type DetParser s a = [s] -> a
some :: Parser s a -> DetParser s a
some p = snd.head.just p

--matching parenthesis
data Tree = Nil2
	    |Bin(Tree,Tree) deriving Show

parens :: Parser Char Tree
parens = (symbol '('
	  <*>
	  parens
	  <*>
	  symbol ')'
	  <*>
	  parens
	  )		<@ (\(_,(x,(_,y))) -> Bin(x,y))
	  <|> succeed Nil2

--need only first part of result tuple [(xs1,v1)] -> [(xs2,v2)] [(xs2,v1)]
(<*) :: Parser s a -> Parser s b -> Parser s a
p1 <* p2 = p1 <*> p2 <@ fst

--need only second part
(*>) :: Parser s a -> Parser s b -> Parser s b
p1 *> p2 = p1 <*> p2 <@ snd

--priorities
infixr 6 <*, *>

--new parens
open = symbol '('
close = symbol ')'

parens' :: Parser Char Tree
parens' = (open *> parens' <* close) <*> parens' <@ Bin	--will apply Bin to (x,y)
	  <|>succeed Nil2
	  
--get nesting depth
nesting :: Parser Char Int
nesting = (open *> nesting <* close) <*> nesting <@ f
	  <|>succeed 0
  where f (x,y) = max (1+x) y
	
--nesting and parens abstracted
foldparens :: ((a,a)->a) -> a -> Parser Char a
foldparens f e = p
  where	p = (open *> p <* close) <*> p <@ f
	    <|>succeed e

--list from tuple
--list' :: (a,a) -> [a]
list' (x,xs) = x:xs

--repetitions of a parser
many :: Parser s a -> Parser s [a]
many p = p <*> many p	<@ (\(x,y) -> x:y)
	  <|> epsilon	<@ (\_ -> [])

--combinator with built-in cons
(<:*>) :: Parser s a -> Parser s [a] -> Parser s [a]
p1 <:*> p2 = p1 <*> p2 <@ (\(x,y) -> x:y)

--new many with <:*>
many' :: Parser s a -> Parser s [a]
many' p = p <:*> many' p <|> succeed []

--parsing a natural number
natural :: Parser Char Int
natural = many digit <@ foldl f 0
  where f a b = a*10 + b
	
--many1, reports error if input is empty
many1 :: Parser s a -> Parser s [a]
many1 p = p <*> many p <@ (\(x,y) -> x:y)

--option combinator, used for 0 or 1 matches, returns a list of results
option :: Parser s a -> Parser s [a]
option p = p <@ (\x -> [x])
	     <|> succeed []
	     
--parser to remove boundary symbols
pack :: Parser s a -> Parser s b -> Parser s c -> Parser s b
pack s1 p s2 = s1 *> p <* s2

--specialization of pack
parenthesized p = pack open p close
bracketed p = pack (symbol '{') p (symbol '}')
compound p = pack (token "begin") p (token "end")

--create list from items separated by some delimiter like comma or semi-colon
listOf :: Parser s a -> Parser s b -> Parser s [a]
listOf p s = p <*> many (s *> p) <@ (\(x,y) -> x:y)
	     <|> succeed []

--common lists
commaList, semicList :: Parser Char a -> Parser Char [a]
commaList p = listOf p (symbol ',')
semicList p = listOf p (symbol ';')

--sequence
sequence' :: [Parser s a] -> Parser s [a]
sequence' = foldr (<:*>) (succeed [])

--choice
choice :: [Parser s a] -> Parser s a
choice = foldr (<|>) fail'

--in contrast to listof the operators are kept in chainl. The parsers for the operators are expected to yield functions.
chainl :: Parser s a -> Parser s (a->a->a) -> Parser  s a
chainl p s = p <*> many (s <*> p) <@ f
  where f = uncurry (foldl (flip ap2))
	ap2 (op,y) x = x `op` y

--optional applies function
p <?@ (no, yes) = p <@ f
  where f [] = no
	f [x] = yes x

--identifier
identifier :: Parser Char [Char]
identifier = many1 (satisfy isAlpha)

--take first element from the list of successes
first :: Parser a b -> Parser a b
first p xs 
  | null r = []
  | otherwise = [head r]
  where r = p xs
	
greedy = first.many

greedy1 = first.many1
  
------------------------------------
------------------Parser Start------
------------------------------------
-- program → {fundef }∗ exp
-- fundef
-- → fname {var}∗ = exp
-- exp → con | var | exp + exp | exp − exp | fname {exp}∗ |
-- exp == exp | if exp then exp else exp | exp : exp |
-- car exp | cdr exp | null exp | [exp {, exp}∗ ] | (exp)
-- con → intlit | boollit| nil

type Fname = String
type Var = String

data Program = Prog [Fundef] Exp deriving Show
data Fundef = Fun String [String] Exp deriving Show
data Exp = I Int | V Var | B Bool | Nil | Fname String | App Exp Exp deriving Show

getInt :: Parser Char Exp
getInt = first natural <@ (\x -> I x)

getBool :: Parser Char Exp
getBool = first (token "True" <|> token "False") <@ (\x -> B (read x::Bool))

getVar :: Parser Char Exp
getVar = first identifier <@ (\x -> V x)

operator

--expr :: Parser Char Exp
expr =
  (sp (getVar <|> getBool <|> getInt)
   <*>
   sp (symbol '+')
   <*>
   sp (getVar  <|> getBool <|> getInt)
   ) <@ (\(x,(y,z)) -> App (App (Fname (y:[])) x) z)
   
 