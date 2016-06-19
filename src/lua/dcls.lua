DCLS = {
    -- get()
}

local function iter_boundary (cur, id, can_cross)
    return function ()
        while cur do
            local c = cur
            cur = cur.__par
            if c.tag == 'Block' then
                return c
            elseif can_cross then
                -- continue
            elseif c.tag=='Async' or string.sub(c.tag,1,7)=='_Async_' then
                -- see if varlist matches id to can_cross the boundary
                -- async (a,b,c) do ... end
                local can_cross2 = false

                local varlist
                if c.tag == '_Async_Isr' then
                    _,varlist = unpack(c)
                else
                    varlist = unpack(c)
                end

                if varlist then
                    for _, ID_int in ipairs(varlist) do
                        if ID_int[1] == id then
                            can_cross2 = true
                            break
                        end
                    end
                end
                if not can_cross2 then
                    return nil
                end
            elseif c.tag=='Data' or c.tag=='Code' or
                   c.tag=='Extcall' or c.tag=='Extreq'
            then
                return nil
            end
        end
    end
end

local function dcls_new (blk, me, can_cross)
    AST.asr(blk, 'Block')

    local old = DCLS.get(blk, me.id, can_cross)
    local implicit = (me.is_implicit and 'implicit ') or ''
    if old and (not old.is_predefined) then
        WRN(false, me, old and
            implicit..'declaration of "'..me.id..'" hides previous declaration'..
                ' ('..old.ln[1]..' : line '..old.ln[2]..')')
    end

    blk.dcls[#blk.dcls+1] = me
    blk.dcls[me.id] = me
end

function DCLS.get (blk, id, can_cross)
    AST.asr(blk, 'Block')
    for blk in iter_boundary(blk,id,can_cross) do
        local dcl = blk.dcls[id]
        if dcl then
            dcl.is_used = true
            return AST.copy(dcl)
        end
    end
    return nil
end

function DCLS.asr (me, blk, id, can_cross, err)
    local ret = DCLS.get(blk, id, can_cross)
    if ret then
        return ret
    else
        local data = AST.par(blk, 'Data')
        if data then
            ASR(false, me, 
                'invalid member access : "'..
                err..  '" has no member "'..id..'" : '..
                '`data´ "'..data.id..
                '" ('..data.ln[1]..':'..  data.ln[2]..')')
        else
            ASR(false, me,
                err..' "'..id..'" is not declared')
        end
    end
end

-- native declarations are allowed until `native/end´
local native_end = false

F = {
    -- Primitive types: id / is_num
    __prims = function (blk)
        local prims = {
            bool  = { is_num=false, is_int=false },
            byte  = { is_num=true,  is_int=true  },
            f32   = { is_num=true,  is_int=false },
            f64   = { is_num=true,  is_int=false },
            float = { is_num=true,  is_int=false },
            int   = { is_num=true,  is_int=true  },
            s16   = { is_num=true,  is_int=true  },
            s32   = { is_num=true,  is_int=true  },
            s64   = { is_num=true,  is_int=true  },
            s8    = { is_num=true,  is_int=true  },
            ssize = { is_num=true,  is_int=true  },
            u16   = { is_num=true,  is_int=true  },
            u32   = { is_num=true,  is_int=true  },
            u64   = { is_num=true,  is_int=true  },
            u8    = { is_num=true,  is_int=true  },
            uint  = { is_num=true,  is_int=true  },
            usize = { is_num=true,  is_int=true  },
            void  = { is_num=false, is_int=false },
            null  = { is_num=false, is_int=false },
            _     = { is_num=true,  is_int=true  },
        }
        for id, t in pairs(prims) do
            dcls_new(blk, {
                            tag   = 'Prim',
                            id    = id,
                            prim  = t,
                            is_used = true,
                          })
        end
    end,
    Block__PRE = function (me)
        me.dcls = {}
        if F.__prims then
            F.__prims(me)
            F.__prims = nil
        end
    end,
    Block__POS = function (me)
        if AST.par(me,'Data') then
            return
        end

        for _, dcl in pairs(me.dcls) do
            if dcl.tag=='Data' and string.sub(dcl.id,1,1)=='_' then
                -- auto generated
            else
                WRN(dcl.is_used or dcl.is_predefined, dcl,
                    AST.tag2id[dcl.tag]..' "'..dcl.id..'" declared but not used')
            end
        end
    end,

    ---------------------------------------------------------------------------

-- NEW

    -- LOC

    Var = function (me)
        local _,_,id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)
    end,

    Vec = function (me)
        local _,_,_,id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)
    end,

    Pool = function (me)
        local _,_,_,id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)
    end,

    Evt = function (me)
        local Typelist,_,id = unpack(me)
        me.id = id

        -- no modifiers allowed
        for _, Type in ipairs(Typelist) do
            local id, mod = unpack(Type)
            assert(id.dcl,'bug found')
            ASR(id.dcl.tag=='Prim', me,
                'invalid event type : must be primitive')
            ASR(not mod, me,
                mod and 'invalid event type : cannot use `'..mod..'´')
        end

        dcls_new(AST.par(me,'Block'), me)
    end,

    -- NATIVE

    Nat_End = function (me)
        native_end = true
    end,
    Nat__PRE = function (me)
        local _,_,id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)

        ASR(not native_end, me,
            'native declarations are disabled')

        if id=='_{}' or id=='_char' then
            me.is_predefined = true
        end
    end,

    -- EXT

    Extcall_proto = 'Extcall_impl',
    Extcall_impl = function (me)
        local grp, _, id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)
    end,

    Ext = function (me)
        local _, grp, id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)
    end,

    -- CODE / DATA

    Code = function (me)
        local _,_,id,_,_blk = unpack(me)
        me.id = id

        local dcl = DCLS.get(AST.par(me,'Block'), me.id, true)
        if (not dcl) or dcl.blk then
        --if not (dcl and dcl.blk) then
            dcls_new(AST.par(me,'Block'), me)
            dcl = me
        end

        -- CHECK prototype
        if me ~= dcl then
            -- ...
        end
        if blk then
            assert(not dcl.blk)
            dcl.blk = blk
        end
    end,

    Data = function (me)
        local id = unpack(me)
        me.id = id
        dcls_new(AST.par(me,'Block'), me)
    end,
    ---------------------------------------------------------------------------

-- GET: ID -> DCL

    ID_prim = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'primitive identifier')
    end,
    ID_nat = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'native identifier')
    end,
    ID_ext = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'external identifier')
    end,
    ID_abs = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, true, 'abstraction')
    end,

    ID_int = function (me)
        local id = unpack(me)
        me.dcl = DCLS.asr(me, AST.par(me,'Block'), id, false, 'internal identifier')
    end,

    ---------------------------------------------------------------------------

    Ref__POS = function (me)
        local id = unpack(me)

        if id == 'every' then
            local _, ID_ext, i = unpack(me)
            assert(id == 'every')
            AST.asr(ID_ext,'ID_ext')
            do
                local _, input = unpack(ID_ext.dcl)
                assert(input == 'input')
            end
            local Typelist = AST.asr(unpack(ID_ext.dcl), 'Typelist')
            local Type = Typelist[i]
            return AST.copy(Type)

        elseif id == 'escape' then
            local _, esc = unpack(me)
            local lbl1 = unpack(esc)
            local do_ = nil
            for n in AST.iter() do
                if n.tag=='Async' or string.sub(n.tag,1,7)=='_Async' or
                   n.tag=='Data'  or n.tag=='Code_impl' or
                   n.tag=='Extcall_impl' or n.tag=='Extreq_impl'
                then
                    break
                end
                if n.tag == 'Do' then
                    local lbl2 = unpack(n)
                    if lbl1 == lbl2 then
                        do_ = n
                        break
                    end
                end
            end
            ASR(do_, esc, 'invalid `escape´ : no matching enclosing `do´')
            local _,_,to,op = unpack(do_)
            local set = AST.asr(me.__par,'Set_Exp')
            local fr = unpack(set)
            if to and type(to)~='boolean' then
                ASR(type(fr)~='boolean', me,
                    'invalid `escape´ : expected expression')
                set[3] = op
                return AST.copy(to)
            else
                ASR(type(fr)=='boolean', me,
                    'invalid `escape´ : unexpected expression')
                set.tag = 'Nothing'
                return AST.node('Nothing', me.ln)
            end
        else
AST.dump(me)
error'TODO'
        end
    end,
}

AST.visit(F)