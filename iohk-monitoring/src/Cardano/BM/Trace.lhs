
\subsection{Cardano.BM.Trace}
\label{code:Cardano.BM.Trace}

%if style == newcode
\begin{code}
{-# LANGUAGE RankNTypes #-}

module Cardano.BM.Trace
    (
      Trace
    , stdoutTrace
    , Tracer.nullTracer
    , traceInTVar
    , traceInTVarIO
    , traceInTVarIOConditionally
    -- * context naming
    , appendName
    , modifyName
    -- * utils
    , natTrace
    , evalFilters
    -- * log functions
    , traceNamedObject
    , traceNamedItem
    , logAlert,     logAlertS
    , logCritical,  logCriticalS
    , logDebug,     logDebugS
    , logEmergency, logEmergencyS
    , logError,     logErrorS
    , logInfo,      logInfoS
    , logNotice,    logNoticeS
    , logWarning,   logWarningS
    ) where

import           Control.Concurrent.MVar (MVar, newMVar, withMVar)
import qualified Control.Concurrent.STM.TVar as STM
import           Control.Monad.IO.Class (MonadIO, liftIO)
import           Control.Monad (when)
import qualified Control.Monad.STM as STM
import           Data.Aeson.Text (encodeToLazyText)
import           Data.Functor.Contravariant (Contravariant (..))
import           Data.Maybe (fromMaybe)
import           Data.Monoid ((<>))
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import           Data.Text.Lazy (toStrict)
import           System.IO.Unsafe (unsafePerformIO)

import qualified Cardano.BM.Configuration as Config
import           Cardano.BM.Data.LogItem
import           Cardano.BM.Data.Severity
import           Cardano.BM.Data.Trace
import           Cardano.BM.Data.SubTrace
import qualified Cardano.BM.Tracer as Tracer
import           Cardano.BM.Tracer (Tracer (..), tracingWith)

\end{code}
%endif

\subsubsection{Utilities}
Natural transformation from monad |m| to monad |n|.
\begin{code}
natTrace :: (forall x . m x -> n x) -> Trace m a -> Trace n a
natTrace nat trace0 = Tracer.natTracer nat trace0

\end{code}

\subsubsection{Enter new named context}\label{code:appendName}\index{appendName}
A new context name is added.
\begin{code}
appendName :: MonadIO m => LoggerName -> Trace m a -> m (Trace m a)
appendName name =
    modifyName (\prevLoggerName -> appendWithDot name prevLoggerName)


appendWithDot :: LoggerName -> LoggerName -> LoggerName
appendWithDot "" newName = newName
appendWithDot xs ""      = xs
appendWithDot xs newName = xs <> "." <> newName

\end{code}

\subsubsection{Change named context}\label{code:modifyName}\index{modifyName}
The context name is overwritten.
\begin{code}
modifyName :: MonadIO m => (LoggerName -> LoggerName) -> Trace m a -> m (Trace m a)
modifyName f trace0 = return $ modifyNameBase f trace0

modifyNameBase
    :: (LoggerName -> LoggerName)
    -> Tracer m (LogObject a)
    -> Tracer m (LogObject a)
modifyNameBase k = contramap f
  where
    f (LogObject name meta item) = LogObject (k name) meta item

\end{code}

\subsubsection{Contramap a trace and produce the naming context}
\begin{code}
named :: Tracer m (LogObject a) -> Tracer m (LOMeta, LOContent a)
named = contramap $ uncurry (LogObject mempty)

\end{code}

\subsubsection{Trace a |LogObject| through}
\label{code:traceNamedObject}\index{traceNamedObject}
\begin{code}
traceNamedObject
    :: MonadIO m
    => Trace m a
    -> (LOMeta, LOContent a)
    -> m ()
traceNamedObject logTrace lo =
    tracingWith (named logTrace) lo

\end{code}

\subsubsection{Evaluation of |FilterTrace|}\label{code:evalFilters}\index{evalFilters}

A filter consists of a |DropName| and a list of |UnhideNames|. If the context name matches
the |DropName| filter, then at least one of the |UnhideNames| must match the name to have
the evaluation of the filters return |True|.

\begin{code}
evalFilters :: [(DropName, UnhideNames)] -> LoggerName -> Bool
evalFilters fs nm =
    all (\(no, yes) -> if (dropFilter nm no) then (unhideFilter nm yes) else True) fs
  where
    dropFilter :: LoggerName -> DropName -> Bool
    dropFilter name (Drop sel) = {-not-} (matchName name sel)
    unhideFilter :: LoggerName -> UnhideNames -> Bool
    unhideFilter _ (Unhide []) = False
    unhideFilter name (Unhide us) = any (\sel -> matchName name sel) us
    matchName :: LoggerName -> NameSelector -> Bool
    matchName name (Exact name') = name == name'
    matchName name (StartsWith prefix) = T.isPrefixOf prefix name
    matchName name (EndsWith postfix) = T.isSuffixOf postfix name
    matchName name (Contains name') = T.isInfixOf name' name
\end{code}

\subsubsection{Concrete Trace on stdout}\label{code:stdoutTrace}\index{stdoutTrace}

This function returns a trace with an action of type "|LogObject a -> IO ()|"
which will output a text message as text and all others as JSON encoded representation
to the console.

\todo[inline]{TODO remove |locallock|}
%if style == newcode
\begin{code}
{-# NOINLINE locallock #-}
\end{code}
%endif
\begin{code}
locallock :: MVar ()
locallock = unsafePerformIO $ newMVar ()
\end{code}

\begin{code}
stdoutTrace :: Tracer IO (LogObject T.Text)
stdoutTrace = Tracer $ \(LogObject logname _ lc) ->
    withMVar locallock $ \_ ->
        case lc of
            (LogMessage logItem) ->
                    output logname $ logItem
            obj ->
                    output logname $ toStrict (encodeToLazyText obj)
  where
    output nm msg = TIO.putStrLn $ nm <> " :: " <> msg

\end{code}


\subsubsection{Concrete Trace into a |TVar|}\label{code:traceInTVar}\label{code:traceInTVarIO}\index{traceInTVar}\index{traceInTVarIO}

\begin{code}
traceInTVar :: STM.TVar [a] -> Tracer STM.STM a
traceInTVar tvar = Tracer $ \a -> STM.modifyTVar tvar ((:) a)

traceInTVarIO :: STM.TVar [LogObject a] -> Tracer IO (LogObject a)
traceInTVarIO tvar = Tracer $ \ln ->
                         STM.atomically $ STM.modifyTVar tvar ((:) ln)

traceInTVarIOConditionally :: STM.TVar [LogObject a] -> Config.Configuration -> Tracer IO (LogObject a)
traceInTVarIOConditionally tvar config =
    Tracer $ \item@(LogObject loggername meta _) -> do
        globminsev  <- Config.minSeverity config
        globnamesev <- Config.inspectSeverity config loggername
        let minsev = max globminsev $ fromMaybe Debug globnamesev

        subTrace <- fromMaybe Neutral <$> Config.findSubTrace config loggername
        let doOutput = subtraceOutput subTrace item

        when ((severity meta) >= minsev && doOutput) $
            STM.atomically $ STM.modifyTVar tvar ((:) item)

        case subTrace of
            TeeTrace secName ->
                STM.atomically $ STM.modifyTVar tvar ((:) item{ loName = secName })
            _ -> return ()

subtraceOutput :: SubTrace -> LogObject a -> Bool
subtraceOutput subTrace (LogObject loname _ loitem) =
    case subTrace of
        FilterTrace filters ->
            case loitem of
                LogValue name _ ->
                    evalFilters filters (loname <> "." <> name)
                _ ->
                    evalFilters filters loname
        DropOpening -> case loitem of
                        ObserveOpen _ -> False
                        _             -> True
        NoTrace     -> False
        _           -> True

\end{code}

\subsubsection{Enter message into a trace}\label{code:traceNamedItem}\index{traceNamedItem}
The function |traceNamedItem| creates a |LogObject| and threads this through
the action defined in the |Trace|.

\begin{code}
traceNamedItem
    :: MonadIO m
    => Trace m a
    -> PrivacyAnnotation
    -> Severity
    -> a
    -> m ()
traceNamedItem trace0 p s m =
    traceNamedObject trace0 =<<
        (,) <$> liftIO (mkLOMeta s p)
            <*> pure (LogMessage m)

\end{code}

\subsubsection{Logging functions}
\label{code:logDebug}\index{logDebug}
\label{code:logDebugS}\index{logDebugS}
\label{code:logInfo}\index{logInfo}
\label{code:logInfoS}\index{logInfoS}
\label{code:logNotice}\index{logNotice}
\label{code:logNoticeS}\index{logNoticeS}
\label{code:logWarning}\index{logWarning}
\label{code:logWarningS}\index{logWarningS}
\label{code:logError}\index{logError}
\label{code:logErrorS}\index{logErrorS}
\label{code:logCritical}\index{logCritical}
\label{code:logCriticalS}\index{logCriticalS}
\label{code:logAlert}\index{logAlert}
\label{code:logAlertS}\index{logAlertS}
\label{code:logEmergency}\index{logEmergency}
\label{code:logEmergencyS}\index{logEmergencyS}
\begin{code}
logDebug, logInfo, logNotice, logWarning, logError, logCritical, logAlert, logEmergency
    :: MonadIO m => Trace m a -> a -> m ()
logDebug     logTrace = traceNamedItem logTrace Public Debug
logInfo      logTrace = traceNamedItem logTrace Public Info
logNotice    logTrace = traceNamedItem logTrace Public Notice
logWarning   logTrace = traceNamedItem logTrace Public Warning
logError     logTrace = traceNamedItem logTrace Public Error
logCritical  logTrace = traceNamedItem logTrace Public Critical
logAlert     logTrace = traceNamedItem logTrace Public Alert
logEmergency logTrace = traceNamedItem logTrace Public Emergency

logDebugS, logInfoS, logNoticeS, logWarningS, logErrorS, logCriticalS, logAlertS, logEmergencyS
    :: MonadIO m => Trace m a -> a -> m ()
logDebugS     logTrace = traceNamedItem logTrace Confidential Debug
logInfoS      logTrace = traceNamedItem logTrace Confidential Info
logNoticeS    logTrace = traceNamedItem logTrace Confidential Notice
logWarningS   logTrace = traceNamedItem logTrace Confidential Warning
logErrorS     logTrace = traceNamedItem logTrace Confidential Error
logCriticalS  logTrace = traceNamedItem logTrace Confidential Critical
logAlertS     logTrace = traceNamedItem logTrace Confidential Alert
logEmergencyS logTrace = traceNamedItem logTrace Confidential Emergency

\end{code}
