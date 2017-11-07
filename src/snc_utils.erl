-module(snc_utils).
-include("snc_protocol.hrl").
-include_lib("xmerl/include/xmerl.hrl").
-export([to_xml_doc/1,
         format_data/2,
         to_pretty_xml_doc/1]).


%%%-----------------------------------------------------------------
%%% Indentation of XML code
indent(Bin) ->
    String = normalize(hide_password(Bin)),
    IndentedString =
        case erase(part_of_line) of
            undefined ->
                indent1(String,[]);
            Part ->
                indent1(lists:reverse(Part)++String,erase(indent))
        end,
    unicode:characters_to_binary(IndentedString).

%% Normalizes the XML document by removing all space and newline
%% between two XML tags.
%% Returns a list, no matter if the input was a list or a binary.
normalize(Bin) ->
    re:replace(Bin,<<">[ \r\n\t]+<">>,<<"><">>,[global,{return,list},unicode]).


indent1("<?"++Rest1,Indent1) ->
    %% Prolog
    {Line,Rest2,Indent2} = indent_line(Rest1,Indent1,[$?,$<]),
    Line++indent1(Rest2,Indent2);
indent1("</"++Rest1,Indent1) ->
    %% Stop tag
    case indent_line1(Rest1,Indent1,[$/,$<]) of
        {[],[],_} ->
            [];
        {Line,Rest2,Indent2} ->
            "\n"++Line++indent1(Rest2,Indent2)
    end;
indent1("<"++Rest1,Indent1) ->
    %% Start- or empty tag
    put(tag,get_tag(Rest1)),
    case indent_line(Rest1,Indent1,[$<]) of
        {[],[],_} ->
            [];
        {Line,Rest2,Indent2} ->
            "\n"++Line++indent1(Rest2,Indent2)
    end;
indent1([H|T],Indent) ->
    [H|indent1(T,Indent)];
indent1([],_Indent) ->
    [].

indent_line("?>"++Rest,Indent,Line) ->
    %% Prolog
    {lists:reverse(Line)++"?>",Rest,Indent};
indent_line("/></"++Rest,Indent,Line) ->
    %% Empty tag, and stop of parent tag -> one step out in indentation
    {Indent++lists:reverse(Line)++"/>","</"++Rest,Indent--"  "};
indent_line("/>"++Rest,Indent,Line) ->
    %% Empty tag, then probably next tag -> keep indentation
    {Indent++lists:reverse(Line)++"/>",Rest,Indent};
indent_line("></"++Rest,Indent,Line) ->
    LastTag = erase(tag),
    case get_tag(Rest) of
        LastTag ->
            %% Start and stop tag, but no content
            indent_line1(Rest,Indent,[$/,$<,$>|Line]);
        _ ->
            %% Stop tag completed, and then stop tag of parent -> one step out
            {Indent++lists:reverse(Line)++">","</"++Rest,Indent--"  "}
    end;
indent_line("><"++Rest,Indent,Line) ->
    %% Stop tag completed, and new tag comming -> keep indentation
    {Indent++lists:reverse(Line)++">","<"++Rest,"  "++Indent};
indent_line("</"++Rest,Indent,Line) ->
    %% Stop tag starting -> search for end of this tag
    indent_line1(Rest,Indent,[$/,$<|Line]);
indent_line([H|T],Indent,Line) ->
    indent_line(T,Indent,[H|Line]);
indent_line([],Indent,Line) ->
    %% The line is not complete - will be continued later
    put(part_of_line,Line),
    put(indent,Indent),
    {[],[],Indent}.

indent_line1("></"++Rest,Indent,Line) ->
    %% Stop tag completed, and then stop tag of parent -> one step out
    {Indent++lists:reverse(Line)++">","</"++Rest,Indent--"  "};
indent_line1(">"++Rest,Indent,Line) ->
    %% Stop tag completed -> keep indentation
    {Indent++lists:reverse(Line)++">",Rest,Indent};
indent_line1([H|T],Indent,Line) ->
    indent_line1(T,Indent,[H|Line]);
indent_line1([],Indent,Line) ->
    %% The line is not complete - will be continued later
    put(part_of_line,Line),
    put(indent,Indent),
    {[],[],Indent}.

format_data(How,Data) ->
    %% Assuming that the data is encoded as UTF-8.  If it is not, then
    %% the printout might be wrong, but the format function will not
    %% crash!
    %% FIXME: should probably read encoding from the data and do
    %% unicode:characters_to_binary(Data,InEncoding,utf8) when calling
    %% log/3 instead of assuming utf8 in as done here!
    do_format_data(How,unicode:characters_to_binary(Data)).

do_format_data(raw,Data) ->
    io_lib:format("~n~ts~n",[hide_password(Data)]);
do_format_data(pretty,Data) ->
    maybe_io_lib_format(indent(Data));
do_format_data(html,Data) ->
    maybe_io_lib_format(html_format(Data)).

maybe_io_lib_format(<<>>) ->
    [];
maybe_io_lib_format(String) ->
    io_lib:format("~n~ts~n",[String]).

%%%-----------------------------------------------------------------
%%% Hide password elements from XML data
hide_password(Bin) ->
    re:replace(Bin,<<"(<password[^>]*>)[^<]*(</password>)">>,<<"\\1*****\\2">>,
               [global,{return,binary},unicode]).

%%%-----------------------------------------------------------------
%%% HTML formatting
html_format(Bin) ->
    binary:replace(indent(Bin),<<"<">>,<<"&lt;">>,[global]).

get_tag("/>"++_) ->
    [];
get_tag(">"++_) ->
    [];
get_tag([H|T]) ->
    [H|get_tag(T)];
get_tag([]) ->
    %% The line is not complete - will be continued later.
    [].

to_xml_doc(SimpleXml) ->
    Prolog = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
    Xml = unicode:characters_to_binary(
            xmerl:export_simple([SimpleXml],
                                xmerl_xml,
                                [#xmlAttribute{name=prolog,
                                               value=Prolog}])),
    <<Xml/binary,?END_TAG/binary>>.

to_pretty_xml_doc(SimpleXml) ->
    indent(to_xml_doc(SimpleXml)).
