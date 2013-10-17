#!/usr/bin/env lua

_RUNTESTS = true

dofile 'pak.lua'

T = nil

STATS = {
    count   = 0,
    mem     = 0,
    trails  = 0,
    bytes   = 0,
}

function check (mod)
    assert(T[mod]==nil or T[mod]==false or type(T[mod])=='string')
    local ok, msg = pcall(dofile, mod..'.lua')
    if T[mod]~=nil then
        assert(string.find(msg, T[mod], nil, true), tostring(msg))
        return false
    else
        assert(ok==true, msg)
        return true
    end
end

Test = function (t)
    T = t
    local source = T[1]
    --local source = 'C _fprintf(), _stderr;'..T[1]
    print('\n=============\n---\n'..source..'\n---\n')

    _OPTS = {
        tp_word    = 4,
        tp_off     = 2,
        tp_lbl     = 2,
        warn_nondeterminism = true,

        cpp    = true,
        input  = 'tests.lua',
        source = source,
    }

    --assert(T.todo == nil)
    if T.todo then
        return
    end

    STATS.count = STATS.count   + 1

    dofile 'tp.lua'

    if not check('lines')    then return end
    if not check('parser')   then return end
    if not check('ast')      then return end
    --_AST.dump(_AST.root)
    if not check('adj')      then return end
    if not check('env')      then return end
    if not check('fin')      then return end
    if not check('tight')    then return end
    --dofile 'awaits.lua'
    if not check('props')    then return end
    dofile 'ana.lua'
    dofile 'acc.lua'

    if not check('trails')   then return end
    if not check('sval')     then return end
    if not check('labels')   then return end
    if not check('tmps')     then return end
    if not check('mem')      then return end
    if not check('val')      then return end
    if not check('code')     then return end

    --STATS.mem     = STATS.mem     + _AST.root.mem.max
    STATS.trails  = STATS.trails  + _AST.root.trails_n

--[[
    if T.awaits then
        assert(T.awaits==_AWAITS.n, 'awaits '.._AWAITS.n)
    end
]]

    if T.tot then
        assert(T.tot==_MEM.max, 'mem '.._MEM.max)
    end

    assert(_TIGHT and T.loop or
           not (_TIGHT or T.loop))

    -- ANALYSIS
    --_AST.dump(_AST.root)
    assert((not T.unreachs) and (not T.isForever)) -- move to analysis
    do
        local _defs = { reachs=0, unreachs=0, isForever=false,
                        acc=0, abrt=0, excpt=0 }
        for k, v in pairs(_ANA.ana) do
-- TODO
if k ~= 'excpt' then
if k ~= 'abrt' then
if k ~= 'unreachs' then
            assert( v==_defs[k] and (T.ana==nil or T.ana[k]==nil)
                    or (T.ana and T.ana[k]==v),
                    --or (T.ana and T.ana.acc==_ANALYSIS.acc),
                            k..' = '..tostring(v))
end
end
end
        end
        if T.ana then
            for k, v in pairs(T.ana) do
if k ~= 'excpt' then
if k ~= 'abrt' then
if k ~= 'unreachs' then
                assert( v == _ANA.ana[k],
                            k..' = '..tostring(_ANA.ana[k]))
end
end
end
            end
        end
    end
--[[
]]

    -- RUN

    if not (T.run or T.gcc) then
        assert(T.loop or T.ana, 'missing run value')
        return
    end

    local CEU = './ceu _ceu_tmp.ceu --run-tests 2>&1'
    local EXE = ((not _VALGRIND) and './ceu.exe 2>&1')
             or 'valgrind -q --leak-check=full ./ceu.exe 2>&1'
             --or 'valgrind -q --tool=helgrind ./ceu.exe 2>&1'
    local GCC = 'gcc -Wall -DCEU_DEBUG -ansi -o ceu.exe main.c 2>&1'
    if _PROPS.has_threads then
        GCC = GCC .. ' -lpthread'
    end

    local f = function (src, exp)
        local ceu = assert(io.open('_ceu_tmp.ceu', 'w'))
        ceu:write(src)
        ceu:close()
        assert(os.execute(CEU) == 0)

        local ret = io.popen(GCC):read'*a'
        if T.gcc then
            assert( string.find(ret, T.gcc, nil, true), ret )
            return
        end

        local ret = io.popen(EXE):read'*a'
        assert(not string.find(ret, '==%d+=='), 'valgrind error')
        local v = tonumber( string.match(ret, 'END: (.-)\n') )

        if v then
            assert(v==exp, ret..' vs '..exp..' expected')
        else
            assert( string.find(ret, exp, nil, true) )
        end
    end

    -- T.run = N
    if type(T.run) ~= 'table' then
        print(source)
        f(source, T.run)
    else
        local par = (T.awaits and T.awaits>0 and 'par') or 'par/or'
        source =
            par .. [[ do
                ]]..source..[[
            with
                async do
                    `EVTS
                end
                await FOREVER;
            end
        ]]
        for input, ret2 in pairs(T.run) do
            input = string.gsub(input, '([^;]*)~>(%d[^;]*);?', 'emit %2;')
            input = string.gsub(input, '[ ]*(%d+)[ ]*~>([^;]*);?', 'emit %2=>%1;')
            input = string.gsub(input, '~>([^;]*);?', 'emit %1;')
            local source = string.gsub(source, '`EVTS', input)
            f(source, ret2)
        end
    end

    local f = io.popen('du -b ceu.exe')
    local n = string.match(f:read'*a', '(%d+)')
    STATS.bytes = STATS.bytes + n
    f:close()
end

dofile 'tests.lua'

print([[

=====================================

STATS = {
    count   = ]]..STATS.count  ..[[,
    mem     = ]]..STATS.mem    ..[[,
    trails  = ]]..STATS.trails ..[[,
    bytes   = ]]..STATS.bytes  ..[[,
}
]])

-- w/ threads
--[[
STATS = {
    count   = 1460,
    mem     = 0,
    trails  = 2975,
    bytes   = 12841770,
}


real	5m16.900s
user	4m29.032s
sys	0m42.276s
]]

os.execute('rm -f /tmp/_ceu_*')
