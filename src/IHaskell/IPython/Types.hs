{-# LANGUAGE OverloadedStrings, DeriveDataTypeable, DeriveGeneric #-}
{-# OPTIONS_GHC -fno-warn-unused-binds -fno-warn-name-shadowing -fno-warn-unused-matches -fno-warn-orphans #-}

-- | This module contains all types used to create an IPython language kernel.
module IHaskell.IPython.Types (
    -- * IPython kernel profile
    Profile(..),
    Transport(..),
    Port,
    IP,

    -- * IPython kernelspecs
    KernelSpec(..),

    -- * IPython messaging protocol
    Message(..),
    MessageHeader(..),
    Username,
    Metadata,
    MessageType(..),
    CodeReview(..),
    Width,
    Height,
    StreamType(..),
    ExecutionState(..),
    ExecuteReplyStatus(..),
    HistoryAccessType(..),
    HistoryReplyElement(..),
    LanguageInfo(..),
    replyType,
    showMessageType,

    -- ** IPython display data message
    DisplayData(..),
    MimeType(..),
    extractPlain,
    ) where

import           Control.Monad (mzero)
import           Data.Aeson
import           Data.ByteString (ByteString)
import           Data.List (find)
import           Data.Map (Map)
import           Data.Serialize
import           Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import           Data.Typeable
import           GHC.Generics (Generic)
import           IHaskell.IPython.Message.UUID

------------------ IPython Kernel Profile Types ----------------------
--
-- | A TCP port.
type Port = Int

-- | An IP address.
type IP = String

-- | The transport mechanism used to communicate with the IPython frontend.
data Transport = TCP -- ^ Default transport mechanism via TCP.
  deriving (Show, Read)

-- | A kernel profile, specifying how the kernel communicates.
data Profile =
       Profile
         { ip :: IP                     -- ^ The IP on which to listen.
         , transport :: Transport       -- ^ The transport mechanism.
         , stdinPort :: Port            -- ^ The stdin channel port.
         , controlPort :: Port          -- ^ The control channel port.
         , hbPort :: Port               -- ^ The heartbeat channel port.
         , shellPort :: Port            -- ^ The shell command port.
         , iopubPort :: Port            -- ^ The IOPub port.
         , signatureKey :: ByteString   -- ^ The HMAC encryption key.
         }
  deriving (Show, Read)

-- Convert the kernel profile to and from JSON.
instance FromJSON Profile where
  parseJSON (Object v) = do
    signatureScheme <- v .: "signature_scheme"
    case signatureScheme of
      "hmac-sha256" ->
        Profile <$> v .: "ip"
                <*> v .: "transport"
                <*> v .: "stdin_port"
                <*> v .: "control_port"
                <*> v .: "hb_port"
                <*> v .: "shell_port"
                <*> v .: "iopub_port"
                <*> (Text.encodeUtf8 <$> v .: "key")
      sig -> error $ "Unexpected signature scheme: " ++ sig
  parseJSON _ = fail "Expecting JSON object."

instance ToJSON Profile where
  toJSON profile = object
                     [ "ip" .= ip profile
                     , "transport" .= transport profile
                     , "stdin_port" .= stdinPort profile
                     , "control_port" .= controlPort profile
                     , "hb_port" .= hbPort profile
                     , "shell_port" .= shellPort profile
                     , "iopub_port" .= iopubPort profile
                     , "key" .= Text.decodeUtf8 (signatureKey profile)
                     ]

instance FromJSON Transport where
  parseJSON (String mech) =
    case mech of
      "tcp" -> return TCP
      _     -> fail $ "Unknown transport mechanism " ++ Text.unpack mech
  parseJSON _ = fail "Expected JSON string as transport."

instance ToJSON Transport where
  toJSON TCP = String "tcp"

-------------------- IPython Kernelspec Types ----------------------
data KernelSpec =
       KernelSpec
         {
         -- | Name shown to users to describe this kernel (e.g. "Haskell")
         kernelDisplayName :: String
         -- | Name for the kernel; unique kernel identifier (e.g. "haskell")
         , kernelLanguage :: String
         -- | Command to run to start the kernel. One of the strings maybe @"{connection_file}"@, which will
         -- be replaced by the path to a kernel profile file (see @Profile@) when the command is run.
         , kernelCommand :: [String]
         }
  deriving (Eq, Show)

instance ToJSON KernelSpec where
  toJSON kernelspec = object
                        [ "argv" .= kernelCommand kernelspec
                        , "display_name" .= kernelDisplayName kernelspec
                        , "language" .= kernelLanguage kernelspec
                        ]

------------------ IPython Message Types --------------------
--
-- | A message header with some metadata.
data MessageHeader =
       MessageHeader
         { identifiers :: [ByteString]          -- ^ The identifiers sent with the message.
         , parentHeader :: Maybe MessageHeader  -- ^ The parent header, if present.
         , metadata :: Metadata                 -- ^ A dict of metadata.
         , messageId :: UUID                    -- ^ A unique message UUID.
         , sessionId :: UUID                    -- ^ A unique session UUID.
         , username :: Username                 -- ^ The user who sent this message.
         , msgType :: MessageType               -- ^ The message type.
         }
  deriving (Show, Read)

-- Convert a message header into the JSON field for the header. This field does not actually have
-- all the record fields.
instance ToJSON MessageHeader where
  toJSON header = object
                    [ "msg_id" .= messageId header
                    , "session" .= sessionId header
                    , "username" .= username header
                    , "version" .= ("5.0" :: String)
                    , "msg_type" .= showMessageType (msgType header)
                    ]

-- | A username for the source of a message.
type Username = Text

-- | A metadata dictionary.
type Metadata = Map Text Value

-- | The type of a message, corresponding to IPython message types.
data MessageType = KernelInfoReplyMessage
                 | KernelInfoRequestMessage
                 | ExecuteInputMessage
                 | ExecuteReplyMessage
                 | ExecuteErrorMessage
                 | ExecuteRequestMessage
                 | ExecuteResultMessage
                 | StatusMessage
                 | StreamMessage
                 | DisplayDataMessage
                 | OutputMessage
                 | InputMessage
                 | IsCompleteRequestMessage
                 | IsCompleteReplyMessage
                 | CompleteRequestMessage
                 | CompleteReplyMessage
                 | InspectRequestMessage
                 | InspectReplyMessage
                 | ShutdownRequestMessage
                 | ShutdownReplyMessage
                 | ClearOutputMessage
                 | InputRequestMessage
                 | InputReplyMessage
                 | CommOpenMessage
                 | CommDataMessage
                 | CommCloseMessage
                 | HistoryRequestMessage
                 | HistoryReplyMessage
  deriving (Show, Read, Eq)

showMessageType :: MessageType -> String
showMessageType KernelInfoReplyMessage = "kernel_info_reply"
showMessageType KernelInfoRequestMessage = "kernel_info_request"
showMessageType ExecuteInputMessage = "execute_input"
showMessageType ExecuteReplyMessage = "execute_reply"
showMessageType ExecuteErrorMessage = "error"
showMessageType ExecuteRequestMessage = "execute_request"
showMessageType ExecuteResultMessage = "execute_result"
showMessageType StatusMessage = "status"
showMessageType StreamMessage = "stream"
showMessageType DisplayDataMessage = "display_data"
showMessageType OutputMessage = "pyout"
showMessageType InputMessage = "pyin"
showMessageType IsCompleteRequestMessage = "is_complete_request"
showMessageType IsCompleteReplyMessage = "is_complete_reply"
showMessageType CompleteRequestMessage = "complete_request"
showMessageType CompleteReplyMessage = "complete_reply"
showMessageType InspectRequestMessage = "inspect_request"
showMessageType InspectReplyMessage = "inspect_reply"
showMessageType ShutdownRequestMessage = "shutdown_request"
showMessageType ShutdownReplyMessage = "shutdown_reply"
showMessageType ClearOutputMessage = "clear_output"
showMessageType InputRequestMessage = "input_request"
showMessageType InputReplyMessage = "input_reply"
showMessageType CommOpenMessage = "comm_open"
showMessageType CommDataMessage = "comm_msg"
showMessageType CommCloseMessage = "comm_close"
showMessageType HistoryRequestMessage = "history_request"
showMessageType HistoryReplyMessage = "history_reply"

instance FromJSON MessageType where
  parseJSON (String s) =
    case s of
      "kernel_info_reply"   -> return KernelInfoReplyMessage
      "kernel_info_request" -> return KernelInfoRequestMessage
      "execute_input"       -> return ExecuteInputMessage
      "execute_reply"       -> return ExecuteReplyMessage
      "error"               -> return ExecuteErrorMessage
      "execute_request"     -> return ExecuteRequestMessage
      "execute_result"      -> return ExecuteResultMessage
      "status"              -> return StatusMessage
      "stream"              -> return StreamMessage
      "display_data"        -> return DisplayDataMessage
      "pyout"               -> return OutputMessage
      "pyin"                -> return InputMessage
      "is_complete_request" -> return IsCompleteRequestMessage
      "is_complete_reply"   -> return IsCompleteReplyMessage
      "complete_request"    -> return CompleteRequestMessage
      "complete_reply"      -> return CompleteReplyMessage
      "inspect_request"     -> return InspectRequestMessage
      "inspect_reply"       -> return InspectReplyMessage
      "shutdown_request"    -> return ShutdownRequestMessage
      "shutdown_reply"      -> return ShutdownReplyMessage
      "clear_output"        -> return ClearOutputMessage
      "input_request"       -> return InputRequestMessage
      "input_reply"         -> return InputReplyMessage
      "comm_open"           -> return CommOpenMessage
      "comm_msg"            -> return CommDataMessage
      "comm_close"          -> return CommCloseMessage
      "history_request"     -> return HistoryRequestMessage
      "history_reply"       -> return HistoryReplyMessage
      "status_message"      -> return StatusMessage

      _                     -> fail ("Unknown message type: " ++ show s)
  parseJSON _ = fail "Must be a string."

data LanguageInfo =
       LanguageInfo
         { languageName :: String        -- ^ The language name, e.g. "haskell"
         , languageVersion :: String        -- ^ GHC 7.6.3
         , languageFileExtension :: String        -- ^ .hs
         , languageCodeMirrorMode :: String        -- ^ 'ihaskell'. can be 'null'
         }
  deriving (Show, Eq)

instance ToJSON LanguageInfo where
  toJSON info = object
                  [ "name" .= languageName info
                  , "version" .= languageVersion info
                  , "file_extension" .= languageFileExtension info
                  , "codemirror_mode" .= languageCodeMirrorMode info
                  ]

data CodeReview = CodeComplete
                | CodeIncomplete String -- ^ String to be used to indent next line of input
                | CodeInvalid
                | CodeUnknown
  deriving Show

-- | A message used to communicate with the IPython frontend.
data Message =
             -- | A request from a frontend for information about the kernel.
              KernelInfoRequest { header :: MessageHeader }
             |
             -- | A response to a KernelInfoRequest.
               KernelInfoReply
                 { header :: MessageHeader
                 , protocolVersion :: String -- ^ current protocol version, major and minor
                 , banner :: String -- ^ Kernel information description e.g. (IHaskell 0.8.3.0 GHC 7.10.2)
                 , implementation :: String -- ^ e.g. IHaskell
                 , implementationVersion :: String -- ^ The version of the implementation
                 , languageInfo :: LanguageInfo
                 }
             |
             -- | A request from a frontend to execute some code.
               ExecuteInput
                 { header :: MessageHeader
                 , getCode :: Text         -- ^ The code string.
                 , executionCounter :: Int -- ^ The execution count, i.e. which output this is.
                 }
             |
             -- | A request from a frontend to execute some code.
               ExecuteRequest
                 { header :: MessageHeader
                 , getCode :: Text              -- ^ The code string.
                 , getSilent :: Bool                  -- ^ Whether this should be silently executed.
                 , getStoreHistory :: Bool            -- ^ Whether to store this in history.
                 , getAllowStdin :: Bool              -- ^ Whether this code can use stdin.
                 , getUserVariables :: [Text]   -- ^ Unused.
                 , getUserExpressions :: Map Text Text -- ^ Unused.
                 }
             |
             -- | A reply to an execute request.
               ExecuteReply
                 { header :: MessageHeader
                 , status :: ExecuteReplyStatus          -- ^ The status of the output.
                 , pagerOutput :: [DisplayData]          -- ^ The mimebundles to display in the pager.
                 , executionCounter :: Int               -- ^ The execution count, i.e. which output this is.
                 }
             |
             -- | A reply to an execute request.
               ExecuteResult
                 { header :: MessageHeader
                 , dataResult :: [DisplayData]           -- ^ Key/value pairs (keys are MIME types)
                 , metadataResult :: Metadata            -- ^ Any metadata that describes the data
                 , executionCounter :: Int               -- ^ The execution count, i.e. which output this is.
                 }
             |
             -- | An error reply to an execute request
               ExecuteError
                 { header :: MessageHeader
                 , pagerOutput :: [DisplayData]          -- ^ The mimebundles to display in the pager.
                 , traceback :: [Text]
                 , ename :: Text
                 , evalue :: Text
                 }
             |
               PublishStatus
                 { header :: MessageHeader
                 , executionState :: ExecutionState      -- ^ The execution state of the kernel.
                 }
             |
               PublishStream
                 { header :: MessageHeader
                 , streamType :: StreamType              -- ^ Which stream to publish to.
                 , streamContent :: String               -- ^ What to publish.
                 }
             |
               PublishDisplayData
                 { header :: MessageHeader
                 , source :: String                      -- ^ The name of the data source.
                 , displayData :: [DisplayData]          -- ^ A list of data representations.
                 }
             |
               PublishOutput
                 { header :: MessageHeader
                 , reprText :: String                    -- ^ Printed output text.
                 , executionCount :: Int                 -- ^ Which output this is for.
                 }
             |
               PublishInput
                 { header :: MessageHeader
                 , inCode :: String                      -- ^ Submitted input code.
                 , executionCount :: Int                 -- ^ Which input this is.
                 }
             | Input { header :: MessageHeader, getCode :: Text, executionCount :: Int }
             | Output { header :: MessageHeader, getText :: [DisplayData], executionCount :: Int }
             |
               IsCompleteRequest
                 { header :: MessageHeader
                 , inputToReview :: String               -- ^ The code entered in the repl.
                 }
             |
               IsCompleteReply
                 { header :: MessageHeader
                 , reviewResult :: CodeReview            -- ^ The result of reviewing the code.
                 }
             |
               CompleteRequest
                 { header :: MessageHeader
                 , getCode :: Text  {- ^
            The entire block of text where the line is. This may be useful in the
            case of multiline completions where more context may be needed.  Note: if
            in practice this field proves unnecessary, remove it to lighten the
            messages. json field @code@  -}
                 , getCursorPos :: Int -- ^ Position of the cursor in unicode characters. json field
                                       -- @cursor_pos@
                 }
             |
               CompleteReply
                 { header :: MessageHeader
                 , completionMatches :: [Text]
                 , completionCursorStart :: Int
                 , completionCursorEnd :: Int
                 , completionMetadata :: Metadata
                 , completionStatus :: Bool
                 }
             |
               InspectRequest
                 { header :: MessageHeader
                 -- | The code context in which introspection is requested
                 , inspectCode :: Text
                 -- | Position of the cursor in unicode characters. json field @cursor_pos@
                 , inspectCursorPos :: Int
                 -- | Level of detail desired (defaults to 0). 0 is equivalent to foo?, 1 is equivalent to foo??.
                 , detailLevel :: Int
                 }
             |
               InspectReply
                 { header :: MessageHeader
                 -- | whether the request succeeded or failed
                 , inspectStatus :: Bool
                 -- | whether the request found anything
                 , inspectFound :: Bool
                 -- | @inspectData@ can be empty if nothing is found
                 , inspectData :: [DisplayData]
                 }
             |
               ShutdownRequest
                 { header :: MessageHeader
                 , restartPending :: Bool    -- ^ Whether this shutdown precedes a restart.
                 }
             |
               ShutdownReply
                 { header :: MessageHeader
                 , restartPending :: Bool    -- ^ Whether this shutdown precedes a restart.
                 }
             |
               ClearOutput
                 { header :: MessageHeader
                 , wait :: Bool -- ^ Whether to wait to redraw until there is more output.
                 }
             | RequestInput { header :: MessageHeader, inputPrompt :: String }
             | InputReply { header :: MessageHeader, inputValue :: String }
             |
               CommOpen
                 { header :: MessageHeader
                 , commTargetName :: String
                 , commTargetModule :: String
                 , commUuid :: UUID
                 , commData :: Value
                 }
             | CommData { header :: MessageHeader, commUuid :: UUID, commData :: Value }
             | CommClose { header :: MessageHeader, commUuid :: UUID, commData :: Value }
             |
               HistoryRequest
                 { header :: MessageHeader
                 , historyGetOutput :: Bool  -- ^ If True, also return output history in the resulting
                                             -- dict.
                 , historyRaw :: Bool        -- ^ If True, return the raw input history, else the
                                             -- transformed input.
                 , historyAccessType :: HistoryAccessType -- ^ What history is being requested.
                 }
             | HistoryReply { header :: MessageHeader, historyReply :: [HistoryReplyElement] }
             | SendNothing -- Dummy message; nothing is sent.
  deriving Show


string :: String -> String
string = id

-- Convert message bodies into JSON.
instance ToJSON Message where
  toJSON rep@KernelInfoReply{} =
    object
      [ "protocol_version" .= protocolVersion rep
      , "banner" .= banner rep
      , "implementation" .= implementation rep
      , "implementation_version" .= implementationVersion rep
      , "language_info" .= languageInfo rep
      ]

  toJSON ExecuteRequest
    { getCode = code
    , getSilent = silent
    , getStoreHistory = storeHistory
    , getAllowStdin = allowStdin
    , getUserVariables = userVariables
    , getUserExpressions = userExpressions
    } =
    object
      [ "code" .= code
      , "silent" .= silent
      , "store_history" .= storeHistory
      , "allow_stdin" .= allowStdin
      , "user_variables" .= userVariables
      , "user_expressions" .= userExpressions
      ]

  toJSON ExecuteReply { status = status, executionCounter = counter, pagerOutput = pager } =
    object
      [ "status" .= show status
      , "execution_count" .= counter
      , "payload" .=
        if null pager
          then []
          else map mkObj pager
      , "user_variables" .= (mempty :: Map String String)
      , "user_expressions" .= (mempty :: Map String String)
      ]
    where
      mkObj o = object
                  [ "source" .= string "page"
                  , "line" .= Number 0
                  , "data" .= object [displayDataToJson o]
                  ]
  toJSON PublishStatus { executionState = executionState } =
    object ["execution_state" .= executionState]
  toJSON PublishStream { streamType = streamType, streamContent = content } =
    object ["data" .= content, "name" .= streamType]
  toJSON PublishDisplayData { source = src, displayData = datas } =
    object
      ["source" .= src, "metadata" .= object [], "data" .= object (map displayDataToJson datas)]

  toJSON PublishOutput { executionCount = execCount, reprText = reprText } =
    object
      [ "data" .= object ["text/plain" .= reprText]
      , "execution_count" .= execCount
      , "metadata" .= object []
      ]
  toJSON PublishInput { executionCount = execCount, inCode = code } =
    object ["execution_count" .= execCount, "code" .= code]

  toJSON (CompleteRequest _ code pos) =
    object
      [ "code" .= code
      , "cursor_pos" .= pos
      ]

  toJSON (InspectRequest _ code pos detailLevel) =
    object
      [ "code" .= code
      , "cursor_pos" .= pos
      , "detail_level" .= detailLevel
      ]

  toJSON (CompleteReply _ matches start end metadata status) =
    object
      [ "matches" .= matches
      , "cursor_start" .= start
      , "cursor_end" .= end
      , "metadata" .= metadata
      , "status" .= if status
                      then string "ok"
                      else "error"
      ]

  toJSON i@InspectReply{} =
    object
      [ "status" .= if inspectStatus i
                      then string "ok"
                      else "error"
      , "data" .= object (map displayDataToJson . inspectData $ i)
      , "metadata" .= object []
      , "found" .= inspectStatus i
      ]

  toJSON ShutdownReply { restartPending = restart } =
    object ["restart" .= restart]

  toJSON ClearOutput { wait = wait } =
    object ["wait" .= wait]

  toJSON RequestInput { inputPrompt = prompt } =
    object ["prompt" .= prompt]

  toJSON req@CommOpen{} =
    object
      [ "comm_id" .= commUuid req
      , "target_name" .= commTargetName req
      , "target_module" .= commTargetModule req
      , "data" .= commData req
      ]

  toJSON req@CommData{} =
    object ["comm_id" .= commUuid req, "data" .= commData req]

  toJSON req@CommClose{} =
    object ["comm_id" .= commUuid req, "data" .= commData req]

  toJSON req@HistoryReply{} =
    object ["history" .= map tuplify (historyReply req)]
    where
      tuplify (HistoryReplyElement sess linum res) = (sess, linum, case res of
                                                                     Left inp         -> toJSON inp
                                                                     Right (inp, out) -> toJSON out)

  toJSON req@IsCompleteReply{} =
    object pairs
    where
      pairs =
        case reviewResult req of
          CodeComplete       -> status "complete"
          CodeIncomplete ind -> status "incomplete" ++ indent ind
          CodeInvalid        -> status "invalid"
          CodeUnknown        -> status "unknown"
      status x = ["status" .= Text.pack x]
      indent x = ["indent" .= Text.pack x]

  toJSON body = error $ "Do not know how to convert to JSON for message " ++ show body


-- | Ways in which the frontend can request history. TODO: Implement fields as described in
-- messaging spec.
data HistoryAccessType = HistoryRange
                       | HistoryTail
                       | HistorySearch
  deriving (Eq, Show)

-- | Reply to history requests.
data HistoryReplyElement =
       HistoryReplyElement
         { historyReplySession :: Int
         , historyReplyLineNumber :: Int
         , historyReplyContent :: Either String (String, String)
         }
  deriving (Eq, Show)

-- | Possible statuses in the execution reply messages.
data ExecuteReplyStatus = Ok
                        | Err
                        | Abort
                        | UnknownExecuteReply String

instance FromJSON ExecuteReplyStatus where
  parseJSON (String "ok") = return Ok
  parseJSON (String "error") = return Err
  parseJSON (String "abort") = return Abort
  parseJSON (String s) = return $ UnknownExecuteReply $ Text.unpack s
  parseJSON _ = mzero

instance Show ExecuteReplyStatus where
  show Ok = "ok"
  show Err = "error"
  show Abort = "abort"
  show (UnknownExecuteReply s) = "unknown (" ++ s ++ ")"

-- | The execution state of the kernel.
data ExecutionState = Busy
                    | Idle
                    | Starting
                    | UnknownExecutionState String
  deriving Show

instance FromJSON ExecutionState where
  parseJSON (String "busy") = return Busy
  parseJSON (String "idle") = return Idle
  parseJSON (String "starting") = return Starting
  parseJSON (String s) = return $ UnknownExecutionState $ Text.unpack s
  parseJSON _ = mzero

-- | Print an execution state as "busy", "idle", or "starting".
instance ToJSON ExecutionState where
  toJSON Busy = String "busy"
  toJSON Idle = String "idle"
  toJSON Starting = String "starting"
  toJSON (UnknownExecutionState s) = String $ Text.pack $ "unknown: " ++ show s

-- | Input and output streams.
data StreamType = Stdin
                | Stdout
                | Stderr
  deriving Show

-- | Print a stream as "stdin" or "stdout" strings.
instance ToJSON StreamType where
  toJSON Stdin = String "stdin"
  toJSON Stdout = String "stdout"
  toJSON Stderr = String "stderr"

instance FromJSON StreamType where
  parseJSON (String "stdin") = return Stdin
  parseJSON (String "stdout") = return Stdout
  parseJSON (String "stderr") = return Stderr
  parseJSON _ = mzero

-- | Get the reply message type for a request message type.
replyType :: MessageType -> Maybe MessageType
replyType KernelInfoRequestMessage = Just KernelInfoReplyMessage
replyType ExecuteRequestMessage = Just ExecuteReplyMessage
replyType IsCompleteRequestMessage = Just IsCompleteReplyMessage
replyType CompleteRequestMessage = Just CompleteReplyMessage
replyType InspectRequestMessage = Just InspectReplyMessage
replyType ShutdownRequestMessage = Just ShutdownReplyMessage
replyType HistoryRequestMessage = Just HistoryReplyMessage
replyType CommOpenMessage = Just CommDataMessage
replyType _ = Nothing

-- | Data for display: a string with associated MIME type.
data DisplayData = DisplayData MimeType Text
  deriving (Typeable, Generic)

-- We can't print the actual data, otherwise this will be printed every time it gets computed
-- because of the way the evaluator is structured. See how `displayExpr` is computed.
instance Show DisplayData where
  show (DisplayData typ _) = "DisplayData <" ++ show typ ++ ">"

-- Allow DisplayData serialization
instance Serialize Text where
  put str = put (Text.encodeUtf8 str)
  get = Text.decodeUtf8 <$> get

-- | Convert a MIME type and value into a JSON dictionary pair.
displayDataToJson :: DisplayData -> (Text, Value)
displayDataToJson (DisplayData mimeType dataStr) =
  Text.pack (show mimeType) .= String dataStr


instance Serialize DisplayData

instance Serialize MimeType

-- | Possible MIME types for the display data.
type Width = Int

type Height = Int

data MimeType = PlainText
              | MimeHtml
              | MimeMarkdown
              | MimePng Width Height
              | MimeJpg Width Height
              | MimeSvg
              | MimeLatex
              | MimeJavascript
              | MimeJSON
              | MimeUnknown String
  deriving (Eq, Typeable, Generic)

-- Extract the plain text from a list of displays.
extractPlain :: [DisplayData] -> String
extractPlain disps =
  case find isPlain disps of
    Just (DisplayData PlainText bytestr) -> Text.unpack bytestr
    _                              -> ""
  where
    isPlain (DisplayData mime _) = mime == PlainText

instance Show MimeType where
  show PlainText = "text/plain"
  show MimeHtml = "text/html"
  show MimeMarkdown = "text/markdown"
  show (MimePng _ _) = "image/png"
  show (MimeJpg _ _) = "image/jpeg"
  show MimeSvg = "image/svg+xml"
  show MimeLatex = "text/latex"
  show MimeJavascript = "application/javascript"
  show MimeJSON = "application/json"
  show (MimeUnknown x) = "unknown: " ++ x

instance Read MimeType where
  readsPrec _ "text/plain" = [(PlainText, "")]
  readsPrec _ "text/html" = [(MimeHtml, "")]
  readsPrec _ "text/markdown" = [(MimeMarkdown, "")]
  readsPrec _ "image/png" = [(MimePng 50 50, "")]
  readsPrec _ "image/jpeg" = [(MimeJpg 50 50, "")]
  readsPrec _ "image/jpg" = [(MimeJpg 50 50, "")]
  readsPrec _ "image/svg+xml" = [(MimeSvg, "")]
  readsPrec _ "text/latex" = [(MimeLatex, "")]
  readsPrec _ "application/javascript" = [(MimeJavascript, "")]
  readsPrec _ "application/json" = [(MimeJSON, "")]
  readsPrec _ x = [(MimeUnknown x, "")]