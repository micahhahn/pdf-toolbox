
-- | Parse content stream

module Pdf.Content.Parser
(
  readNextOperator,
  parseContent,
)
where

import Pdf.Core.Exception
import Pdf.Core.Parsers.Object

import Pdf.Content.Ops

import Data.Attoparsec.ByteString.Char8 (Parser)
import qualified Data.Attoparsec.ByteString.Char8 as Parser
import Control.Applicative
import Control.Monad
import Control.Exception hiding (throw)
import System.IO.Streams (InputStream)
import qualified System.IO.Streams as Streams
import qualified System.IO.Streams.Attoparsec as Streams

-- | Read the next operator if any
readNextOperator :: InputStream Expr -> IO (Maybe Operator)
readNextOperator is = message "readNextOperator" $ go []
  where
  go args = do
    expr <- Streams.read is
      -- XXX: it should be handled by stream creator
      `catch` \(Streams.ParseException msg) -> throwIO (Corrupted msg [])
    case expr of
      Nothing -> case args of
                   [] -> return Nothing
                   _ -> throwIO $ Corrupted ("Args without op: " ++ show args) []
      Just (Obj o) -> go (o : args)
      Just (Op o) -> return $ Just (o, reverse args)

-- | Parser expression in a content stream
parseContent :: Parser (Maybe Expr)
parseContent = do
  skipSpace
  expr <- 
    (Parser.endOfInput >> return Nothing) <|>
      fmap Just (fmap Obj parseObject <|>
                 fmap (Op . toOp) (Parser.takeWhile1 isRegularChar))

  case expr of
    Just (Op Op_ID) ->
      Parser.scan
        ('I', 'D')
        ( \(ppChar, pChar) char ->
              if ppChar == 'E' && pChar == 'I'
                then Nothing
                else Just (pChar, char)
        ) >> pure expr
    _ ->
      pure expr

-- Treat comments as spaces
skipSpace :: Parser ()
skipSpace = do
  Parser.skipSpace
  void $ many $ do
    _ <- Parser.char '%'
    Parser.skipWhile $ \c -> c /= '\n' && c /= '\r'
    Parser.skipSpace
