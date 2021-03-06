{-# LANGUAGE OverloadedStrings, ScopedTypeVariables, QuasiQuotes #-}
{-# OPTIONS_GHC -fno-warn-unused-binds -fno-warn-name-shadowing #-}

-- | Description : Parsing messages received from IPython
--
-- This module is responsible for converting from low-level ByteStrings obtained from the 0MQ
-- sockets into Messages. The only exposed function is `parseMessage`, which should only be used in
-- the low-level 0MQ interface.
module IHaskell.IPython.Message.Parser (parseMessage) where

import           Data.Aeson ((.:), (.:?), (.!=), decode, Result(..), Object, Value(..), FromJSON)
import           Data.Aeson.Types (parse, parseEither, Parser)
import           Data.ByteString hiding (unpack)
import qualified Data.ByteString.Lazy as Lazy
import           Data.HashMap.Strict as HM
import           Data.Map (Map, empty)
import           Data.Maybe (fromMaybe)
import           Data.String.Interpolate
import           Data.Text (Text, unpack)
import           Debug.Trace
import           IHaskell.IPython.Types

type LByteString = Lazy.ByteString

-- --- External interface ----- | Parse a message from its ByteString components into a Message.
parseMessage :: [ByteString] -- ^ The list of identifiers sent with the message.
             -> ByteString   -- ^ The header data.
             -> ByteString   -- ^ The parent header, which is just "{}" if there is no header.
             -> ByteString   -- ^ The metadata map, also "{}" for an empty map.
             -> ByteString   -- ^ The message content.
             -> Either String Message      -- ^ A parsed message.
parseMessage idents headerData parentHeader metadata content = case parseHeader idents headerData parentHeader metadata of
  Error s -> Left s
  Success header -> Right $ messageWithoutHeader { header = header } where
    messageType = msgType header
    messageWithoutHeader = parser messageType $ Lazy.fromStrict content

-- --- Module internals ----- | Parse a header from its ByteString components into a MessageHeader.
parseHeader :: [ByteString]  -- ^ The list of identifiers.
            -> ByteString    -- ^ The header data.
            -> ByteString    -- ^ The parent header, or "{}" for Nothing.
            -> ByteString    -- ^ The metadata, or "{}" for an empty map.
            -> Result MessageHeader -- The resulting message header.
parseHeader idents headerData parentHeader metadata = case decode $ Lazy.fromStrict headerData of
  Nothing -> Error $ "Failed to parse header: " ++ show headerData
  Just result -> flip parse result $ \obj -> do
    messageType <- obj .: "msg_type"
    username <- obj .: "username"
    messageUUID <- obj .: "msg_id"
    sessionUUID <- obj .: "session"

    -- Get metadata as a simple map.
    let metadataMap = case decode $ Lazy.fromStrict metadata :: Maybe (Map Text Value) of
          Nothing -> mempty -- TODO: sometimes the values aren't text. Fix this if it causes a problem.
          Just metadataMap -> metadataMap

    return $ MessageHeader
      { identifiers = idents
      , parentHeader = parentResult
      , metadata = metadataMap
      , messageId = messageUUID
      , sessionId = sessionUUID
      , username = username
      , msgType = messageType
      }

  where
    -- If the parent header data is absent, just have Nothing instead.
    parentResult = if parentHeader == "{}"
                     then Nothing
                     else (case parseHeader idents parentHeader "{}" metadata of
                             Success h -> Just h
                             Error _ -> Nothing)


noHeader :: MessageHeader
noHeader = error "No header created"

parser :: MessageType            -- ^ The message type being parsed.
       -> LByteString -> Message -- ^ The parser that converts the body into a message. This message
                                 -- should have an undefined header.
parser KernelInfoRequestMessage = kernelInfoRequestParser
parser ExecuteInputMessage = executeInputParser
parser ExecuteRequestMessage = executeRequestParser
parser ExecuteReplyMessage = executeReplyParser
parser ExecuteErrorMessage = executeErrorParser
parser ExecuteResultMessage = executeResultParser
parser DisplayDataMessage = displayDataParser
parser IsCompleteRequestMessage = isCompleteRequestParser
parser CompleteRequestMessage = completeRequestParser
parser CompleteReplyMessage = completeReplyParser
parser InspectRequestMessage = inspectRequestParser
parser InspectReplyMessage = inspectReplyParser
parser ShutdownRequestMessage = shutdownRequestParser
parser InputReplyMessage = inputReplyParser
parser CommOpenMessage = commOpenParser
parser CommDataMessage = commDataParser
parser CommCloseMessage = commCloseParser
parser HistoryRequestMessage = historyRequestParser
parser StatusMessage = statusMessageParser
parser StreamMessage = streamMessageParser
parser InputMessage = inputMessageParser
parser OutputMessage = outputMessageParser
parser ClearOutputMessage = clearOutputMessageParser
parser other = error $ "Unknown message type " ++ show other

-- | Parse a kernel info request. A kernel info request has no auxiliary information, so ignore the
-- body.
kernelInfoRequestParser :: LByteString -> Message
kernelInfoRequestParser _ = KernelInfoRequest { header = noHeader }

-- | Parse an execute_input response. Fields used are:
executeInputParser :: LByteString -> Message
executeInputParser = requestParser $ \obj -> do
  code <- obj .: "code"
  executionCount <- obj .: "execution_count"
  return $ ExecuteInput noHeader code executionCount

-- | Parse an execute request. Fields used are:
--  1. "code": the code to execute.
--  2. "silent": whether to execute silently.
--  3. "store_history": whether to include this in history.
--  4. "allow_stdin": whether to allow reading from stdin for this code.
executeRequestParser :: LByteString -> Message
executeRequestParser content = case decode content of
  Nothing -> error "Failed to decode message"
  Just decoded ->
    case parse parser decoded of
      Success (code, silent, storeHistory, allowStdin) ->
        ExecuteRequest { header = noHeader
                       , getCode = code
                       , getSilent = silent
                       , getAllowStdin = allowStdin
                       , getStoreHistory = storeHistory
                       , getUserVariables = []
                       , getUserExpressions = Data.Map.empty
                       }
      _ -> error "Failed to parse message"
  where parser obj = do
          code <- obj .: "code"
          silent <- obj .: "silent"
          storeHistory <- obj .: "store_history"
          allowStdin <- obj .: "allow_stdin"

          return (code, silent, storeHistory, allowStdin)

-- | Parse an execute reply
executeReplyParser :: LByteString -> Message
executeReplyParser = requestParser $ \obj -> do
  status <- obj .: "status"
  executionCount <- obj .: "execution_count"
  return $ ExecuteReply noHeader status [] executionCount

-- | Parse an execute reply
executeErrorParser :: LByteString -> Message
executeErrorParser = requestParser $ \obj -> do
  -- executionCount <- obj .: "execution_count"
  traceback <- obj .: "traceback"
  ename <- obj .: "ename"
  evalue <- obj .: "evalue"
  return $ ExecuteError noHeader [] traceback ename evalue

makeDisplayDatas :: Object -> [DisplayData]
makeDisplayDatas dataDict = [DisplayData (read $ unpack mimeType) content |
                             (mimeType, String content) <- HM.toList dataDict]

-- | Parse an execute result
executeResultParser :: LByteString -> Message
executeResultParser = requestParser $ \obj -> do
  executionCount <- obj .: "execution_count"
  dataDict :: Object <- obj .: "data"
  let displayDatas = makeDisplayDatas dataDict
  maybeMetadataDict <- obj .:? "metadata"
  let metadataDict = case maybeMetadataDict of Just d -> d; Nothing -> Data.Map.empty
  return $ ExecuteResult noHeader displayDatas metadataDict executionCount

-- | Parse a display data message
displayDataParser :: LByteString -> Message
displayDataParser = requestParser $ \obj -> do
  dataDict :: Object <- obj .: "data"
  let displayDatas = makeDisplayDatas dataDict
  maybeSource <- obj .:? "source"
  return $ PublishDisplayData noHeader (fromMaybe "" maybeSource) displayDatas

requestParser :: (FromJSON r, Show r) => (r -> Parser Message) -> Lazy.ByteString -> Message
requestParser parser content = case decode content of
  Nothing -> trace "Decode error" SendNothing
  Just decoded -> case parseEither parser $ decoded of
    Right parsed -> parsed
    Left err -> trace ([i|Parse error: #{err}. Decoded was #{decoded}.|]) SendNothing

historyRequestParser :: LByteString -> Message
historyRequestParser = requestParser $ \obj ->
  HistoryRequest noHeader <$> obj .: "output" <*> obj .: "raw" <*> historyAccessType obj
  where
    -- TODO: Implement full history access type parsing from message spec
    historyAccessType obj = do
      accessTypeStr <- obj .: "hist_access_type"
      return $
        case accessTypeStr of
          "range"  -> HistoryRange
          "tail"   -> HistoryTail
          "search" -> HistorySearch
          str      -> error $ "Unknown history access type: " ++ str

statusMessageParser :: LByteString -> Message
statusMessageParser = requestParser $ \obj -> do
  execution_state <- obj .: "execution_state"
  return $ PublishStatus noHeader execution_state

streamMessageParser :: LByteString -> Message
streamMessageParser = requestParser $ \obj -> do
  streamType <- obj .: "name"
  streamContent <- obj .: "text"
  return $ PublishStream noHeader streamType streamContent

inputMessageParser :: LByteString -> Message
inputMessageParser = requestParser $ \obj -> do
  code <- obj .: "code"
  executionCount <- obj .: "execution_count"
  return $ Input noHeader code executionCount

getDisplayDatas :: Maybe Object -> [DisplayData]
getDisplayDatas Nothing = []
getDisplayDatas (Just dataDict) = makeDisplayDatas dataDict

outputMessageParser :: LByteString -> Message
outputMessageParser = requestParser $ \obj -> do
  -- Handle both "data" and "text" keys
  maybeDataDict1 :: Maybe Object <- obj .:? "data"
  let displayDatas1 = getDisplayDatas maybeDataDict1

  maybeDataDict2 :: Maybe Object <- obj .:? "text"
  let displayDatas2 = getDisplayDatas maybeDataDict2

  executionCount <- obj .: "execution_count"
  return $ Output noHeader (displayDatas1 ++ displayDatas2) executionCount

clearOutputMessageParser :: LByteString -> Message
clearOutputMessageParser = requestParser $ \obj -> do
  wait <- obj .: "wait"
  return $ ClearOutput noHeader wait

isCompleteRequestParser :: LByteString -> Message
isCompleteRequestParser = requestParser $ \obj -> do
  code <- obj .: "code"
  return $ IsCompleteRequest noHeader code

completeRequestParser :: LByteString -> Message
completeRequestParser = requestParser $ \obj -> do
  code <- obj .: "code"
  pos <- obj .: "cursor_pos"
  return $ CompleteRequest noHeader code pos

completeReplyParser :: LByteString -> Message
completeReplyParser = requestParser $ \obj -> do
  matches <- obj .: "matches"
  cursorStart <- obj .: "cursor_start"
  cursorEnd <- obj .: "cursor_end"
  maybeMetadata <- obj .:? "metadata"
  statusStr :: String <- obj .: "status"

  let status = statusStr == "ok"

  return $ CompleteReply noHeader matches cursorStart cursorEnd (fromMaybe mempty maybeMetadata) status

inspectRequestParser :: LByteString -> Message
inspectRequestParser = requestParser $ \obj -> do
  code <- obj .: "code"
  pos <- obj .: "cursor_pos"
  dlevel <- obj .: "detail_level"
  return $ InspectRequest noHeader code pos dlevel

inspectReplyParser :: LByteString -> Message
inspectReplyParser = requestParser $ \obj -> do
  found <- obj .: "found"

  maybeDataDict :: Maybe Object <- obj .:? "data"
  let displayDatas = getDisplayDatas maybeDataDict

  -- metadata <- obj .: "metadata"

  statusStr :: String <- obj .: "status"
  let status = statusStr == "ok"

  return $ InspectReply noHeader status found displayDatas

shutdownRequestParser :: LByteString -> Message
shutdownRequestParser = requestParser $ \obj -> do
  code <- obj .: "restart"
  return $ ShutdownRequest noHeader code

inputReplyParser :: LByteString -> Message
inputReplyParser = requestParser $ \obj -> do
  value <- obj .: "value"
  return $ InputReply noHeader value

commOpenParser :: LByteString -> Message
commOpenParser = requestParser $ \obj -> do
  uuid <- obj .: "comm_id"
  targetName <- obj .: "target_name"
  targetModule <- obj .:? "target_module" .!= ""
  value <- obj .: "data"
  return $ CommOpen noHeader targetName targetModule uuid value

commDataParser :: LByteString -> Message
commDataParser = requestParser $ \obj -> do
  uuid <- obj .: "comm_id"
  value <- obj .: "data"
  return $ CommData noHeader uuid value

commCloseParser :: LByteString -> Message
commCloseParser = requestParser $ \obj -> do
  uuid <- obj .: "comm_id"
  value <- obj .: "data"
  return $ CommClose noHeader uuid value
