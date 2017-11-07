%%----------------------------------------------------------------------
%% Type declarations
%%----------------------------------------------------------------------
-type options() :: [option()].

-type option() :: {ssh,host()} | {port,inet:port_number()} | {user,string()} |
                  {password,string()} | {user_dir,string()} |
                  {timeout,timeout()}.

-type session_options() :: [session_option()].
-type session_option() :: {timeout,timeout()}.

-type host() :: inet:hostname() | inet:ip_address().

-type notification() :: {notification, xml_attributes(), notification_content()}.

-type notification_content() :: [event_time()|simple_xml()].

-type event_time() :: {eventTime,xml_attributes(),[xs_datetime()]}.

-type stream_name() :: string().

-type streams() :: [{stream_name(),[stream_data()]}].

-type stream_data() :: {description,string()} |
                       {replaySupport,string()} |
                       {replayLogCreationTime,string()} |
                       {replayLogAgedTime,string()}.

%% See XML Schema for Event Notifications found in RFC5277 for further
%% detail about the data format for the string values.

-type error_reason() :: term().

-type server_id() :: atom().

-type simple_xml() :: {xml_tag(), xml_attributes(), xml_content()} |
                      {xml_tag(), xml_content()} |
                      xml_tag().
-type xml_tag() :: atom().
-type xml_attributes() :: [{xml_attribute_tag(),xml_attribute_value()}].
-type xml_attribute_tag() :: atom().
-type xml_attribute_value() :: string().
-type xml_content() :: [simple_xml() | iolist()].
-type xpath() :: {xpath,string()}.

-type netconf_db() :: running | startup | candidate.
-type xs_datetime() :: string().