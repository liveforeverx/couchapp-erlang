-module(couchapp).
-export([folder_to_json/1, sync/2, compare/2]).

% Options:
% {id, "some"}
% id from folder name = {folder_id, true}
% Host property = {host, "localhost"}
% Port property = {port, 10001}
% DB property = {db, "charging"}
defaults() -> ["127.0.0.1", 5984, "database"].

sync(Folder, Options) ->
    DDocId        = list_to_binary("_design/" ++ proplists:get_value(id, Options)),
    DDocLanguage  = proplists:get_value(language, Options, <<"javascript">>),
    {FolderProps} = folder_to_json(Folder),
    NewProps      = [{<<"_id">>, DDocId}, {<<"language">>, DDocLanguage} | FolderProps],
    NewDesignDoc  = {NewProps},

    [Host, Port, DBPath] = attributes([host, port, db], defaults(), Options),
    DBOptions = case proplists:get_value(user, Options) of
                    undefined -> [];
                    User      -> [{basic_auth, {User, proplists:get_value(password, Options, "")}}]
                end,
    Server   = couchbeam:server_connection(Host, Port, "", DBOptions),
    {ok, DB} = couchbeam:open_db(Server, DBPath),

    case couchbeam:open_doc(DB, DDocId) of
        {ok, {PropsInDB}} ->
            case compare(NewDesignDoc, {proplists:delete(<<"_rev">> , PropsInDB)}) of
                true ->
                    Rev = lists:keyfind(<<"_rev">>, 1, PropsInDB),
                    log_update(Host, Port, DBPath, DDocId),
                    couchbeam:save_doc(DB, {[Rev | NewProps]});
                false ->
                    ok
            end;
        {error, not_found} ->
            log_update(Host, Port, DBPath, DDocId),
            couchbeam:save_doc(DB, NewDesignDoc)
    end.


compare({Res}, {ObjInDB}) -> compare(Res, ObjInDB);
compare([], []) -> false;
compare([], _P) -> true;
compare([{Name, Content}|Res], ObjInDB) ->
    Resal = case proplists:get_value(Name, ObjInDB) of
                undefined ->
                    true;
                Value     ->
                    case {is_tuple(Content), is_tuple(Value)} of
                        {true, true}   -> compare(Content, Value);
                        {false, false} ->
                            case Content == Value of
                                true  -> false;
                                false -> true
                            end;
                        _Other        -> true
                    end
            end,
    case Resal of
        true  ->
            true;
        false ->
            compare(Res, proplists:delete(Name, ObjInDB))
    end.

attributes(Properties, Standarts, Options) ->
    attr_acc(Properties, Standarts, Options, []).

attr_acc([], _, _, Acc) -> lists:reverse(Acc);

attr_acc([Prop|Properties], [Stan|Standarts], Options, Acc) ->
    case proplists:get_value(Prop, Options) of
        undefined ->
            attr_acc(Properties, Standarts, Options, [Stan|Acc]);
        Value     ->
            attr_acc(Properties, Standarts, Options, [Value|Acc])
    end.

folder_to_json(Folder) ->
    case file:list_dir(Folder) of
        {ok, Files} ->
            {[do_entry(Folder, F) || F <- Files]};
        Error -> Error
    end.

do_entry(Directory, Name) ->
    Path = filename:join(Directory, Name),
    case filelib:is_dir(Path) of
        true ->
            {list_to_binary(Name), folder_to_json(Path)};
        false ->
            case file:read_file(Path) of
                {ok, Content} ->
                    {list_to_binary(filename:rootname(Name)), Content};
                {error, Error} ->
                    throw({error, Error})
            end
    end.

log_update(Host, Port, Path, DDoc) ->
    Report = io_lib:format("Pushing design document ~p~nCouchDB: ~s:~p/~s", [DDoc, Host, Port, Path]),
    error_logger:info_report(Report).
