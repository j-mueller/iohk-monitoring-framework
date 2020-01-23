
\subsection{Cardano.BM.Data.Severity}
\label{code:Cardano.BM.Data.Severity}

%if style == newcode
\begin{code}
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE LambdaCase         #-}

module Cardano.BM.Data.Severity
  ( Severity (..)
  , sev2klog
  )
  where

import           Data.Aeson (FromJSON (..), ToJSON)
import           Data.Yaml (withText)

import           GHC.Generics (Generic)

import qualified Katip as K

\end{code}
%endif

\subsubsection{Severity}\label{code:Severity}\index{Severity}\index{Severity!instance of FromJSON}
\label{code:Debug}\index{Severity!Debug}
\label{code:Info}\index{Severity!Info}
\label{code:Notice}\index{Severity!Notice}
\label{code:Warning}\index{Severity!Warning}
\label{code:Error}\index{Severity!Error}
\label{code:Critical}\index{Severity!Critical}
\label{code:Alert}\index{Severity!Alert}
\label{code:Emergency}\index{Severity!Emergency}
The intended meaning of severity codes:

Debug     | detailed information about values and decision flow
Info      | general information of events; progressing properly
Notice    | needs attention; something not progressing properly
Warning   | may continue into an error condition if continued
Error     | unexpected set of event or condition occurred
Critical  | error condition causing degrade of operation
Alert     | a subsystem is no longer operating correctly, likely requires manual intervention
Emergency | at this point, the system can never progress without additional intervention

We were informed by the |Syslog| taxonomy: \url{https://en.wikipedia.org/wiki/Syslog#Severity_level}

\begin{code}
data Severity = Debug
              | Info
              | Notice
              | Warning
              | Error
              | Critical
              | Alert
              | Emergency
                deriving (Show, Eq, Ord, Bounded, Enum, Generic, ToJSON, Read)

instance FromJSON Severity where
    parseJSON = withText "severity" $ \case
                    "Debug"     -> pure Debug
                    "Info"      -> pure Info
                    "Notice"    -> pure Notice
                    "Warning"   -> pure Warning
                    "Error"     -> pure Error
                    "Critical"  -> pure Critical
                    "Alert"     -> pure Alert
                    "Emergency" -> pure Emergency
                    _           -> pure Info   -- catch all

-- translate Severity to Log.Severity
sev2klog :: Severity -> K.Severity
sev2klog = \case
    Debug     -> K.DebugS
    Info      -> K.InfoS
    Notice    -> K.NoticeS
    Warning   -> K.WarningS
    Error     -> K.ErrorS
    Critical  -> K.CriticalS
    Alert     -> K.AlertS
    Emergency -> K.EmergencyS

\end{code}
