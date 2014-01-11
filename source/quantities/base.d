// Written in the D programming language
/++
This module defines the base types for unit and quantity handling.

Copyright: Copyright 2013, Nicolas Sicard
Authors: Nicolas Sicard
License: $(LINK www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
Source: $(LINK https://github.com/biozic/quantities)
+/
module quantities.base;

import quantities.math;
import std.exception;
import std.string;
import std.traits;

version (unittest)
{
    import std.math : approxEqual;
    import quantities.si;
    import quantities.parsing;
}

enum AtRuntime
{
    no = false,
    yes = true
}

/++
Quantity types which holds a value and some dimensions.

The value is stored internally as a field of type N, which defaults to double.
A dimensionless quantity can be cast to a builtin numeric type.

Arithmetic operators (+ - * /), as well as assignment and comparison operators,
are defined when the operations are dimensionally correct, otherwise an error
occurs at compile-time.

RTQuantity can be used at runtime.
+/
struct Quantity(alias dim, N = double, AtRuntime rt = AtRuntime.no)
{
    static assert(isFloatingPoint!N);
    alias runtime = rt;

    /// The type of the underlying scalar value.
    alias valueType = N;
    
    /// The payload
    private N _value;
    
    /// The dimensions of the quantity.
    static if (runtime)
    {
        immutable(Dimensions) dimensions;
        private bool initialized = false;
    }
    else
    {
        alias dimensions = dim;
    }

    private static string checkDim(string dim, bool forceRuntime = false)()
    {
        enum code = `%s(` ~ dim ~ ` == dimensions,
                format("Dimension error: %%s is not compatible with %%s",
                ` ~ dim ~ `.toString(true), dimensions.toString(true))
                );`;
        static if (runtime || forceRuntime)
            return format(code, "enforceEx!DimensionException");
        else
            return format(code, "static assert");
    }

    // Creates a new quantity from another one that is dimensionally consistent
    package this(T)(T other) inout
        if (isQuantity!T)
    {
        static if (runtime) 
        {
            dimensions = other.dimensions;
            initialized = true;
        }
        else
        {
            static if (T.runtime)
                mixin(checkDim!("other.dimensions", true));
            else
                mixin(checkDim!("other.dimensions"));
        }

        _value = other._value;
    }

    // Creates a new compile-time quantity from a raw numeric value
    package this(T)(T value)
        if (isNumeric!T && !runtime)
    {
        _value = value;
    }    

    // Creates a new runtime quantity from a raw numeric value and a dimension
    package this(T)(T value, const(Dimensions) dim = Dimensions.init)
        if (isNumeric!T && runtime)
    {
        _value = value;
        dimensions = dim.idup;
    }   

    package void resetTo(T)(const T other)
        if (isQuantity!T && runtime)
    {
        _value = other._value;
        cast(Dimensions) dimensions = cast(Dimensions) other.dimensions; // Oohoooh...
    }

    /++
    Get the scalar value of this quantity expressed in a combination of
    the base dimensions. This value is actually the payload of the Quantity struct.
    +/
    @property N rawValue() const
    {
        return _value;
    }
    
    /++
    Gets the scalar _value of this quantity expressed in the given target unit.
    +/
    N value(Q)(Q target) const
        if(isQuantity!Q)
    {
        mixin(checkDim!"target.dimensions");
        return _value / target._value;
    }
    ///
    unittest
    {
        auto speed = 100 * meter / (5 * second);
        assert(speed.value(meter/second) == 20);
    }

    /++
    Returns a new quantity where the value is stored in a field of type T.
    +/
    auto store(T)() const
    {
        return Quantity!(dimensions, T, runtime)(_value);
    }
    ///
    unittest
    {
        auto length = meter.store!real;
        assert(is(length.valueType == real));
    }

    // Cast a dimensionless quantity to a scalar numeric type
    T opCast(T)()
        if (isNumeric!T)
    {
        mixin(checkDim!"Dimensions.init");
        return _value;
    }

    // Assign from another quantity
    void opAssign(T)(T other)
        if (isQuantity!T)
    {
        static if (runtime)
        {
            if (!initialized)
            {
                cast(Dimensions) dimensions = cast(Dimensions) other.dimensions; // Oohoooh...
                initialized = true;
            }
            else
                mixin(checkDim!"other.dimensions");
        }
        else
        {
            static if (T.runtime)
                mixin(checkDim!("other.dimensions", true));
            else
                mixin(checkDim!"other.dimensions");
        }
        _value = other._value;
    }

    // Unary + and -
    auto opUnary(string op)() const
        if (op == "+" || op == "-")
    {
        static if (runtime)
            return RTQuantity(mixin(op ~ "_value"), dimensions);
        else
            return Unqual!(typeof(this))(mixin(op ~ "_value"));
    }

    // Add (or substract) two quantities if they share the same dimensions
    auto opBinary(string op, T)(T other) const
        if (isQuantity!T && (op == "+" || op == "-"))
    {
        mixin(checkDim!"other.dimensions");
        static if (runtime)
            return RTQuantity(mixin("_value" ~ op ~ "other._value"), dimensions);
        else
            return Unqual!(typeof(this))(mixin("_value" ~ op ~ "other._value"));
    }

    // Add (or substract) a dimensionless quantity and a scalar
    auto opBinary(string op, T)(T other) const
        if (isNumeric!T && (op == "+" || op == "-"))
    {
        mixin(checkDim!"Dimensions.init");
        static if (runtime)
            return RTQuantity(mixin("_value" ~ op ~ "other"), dimensions);
        else
            return Unqual!(typeof(this))(mixin("_value" ~ op ~ "other"));
    }

    // ditto
    auto opBinaryRight(string op, T)(T other) const
        if (isNumeric!T && (op == "+" || op == "-"))
    {
        return opBinary!op(other);
    }

    // Multiply or divide two quantities
    auto opBinary(string op, T)(T other) const
        if (isQuantity!T && (op == "*" || op == "/"))
    {
        static if (runtime)
        {
            return RTQuantity(
                mixin("_value" ~ op ~ "other._value"),
                mixin("dimensions" ~ op ~ "other.dimensions")
                );
        }
        else
        {
            return Quantity!(mixin("dimensions" ~ op ~ "other.dimensions"), N)(
                mixin("_value" ~ op ~ "other._value"));
        }
    }

    // Multiply or divide a quantity by a scalor factor
    auto opBinary(string op, T)(T other) const
        if (isNumeric!T && (op == "*" || op == "/"))
    {
        static if (runtime)
            return RTQuantity(mixin("_value" ~ op ~ "other"), dimensions);
        else
            return Unqual!(typeof(this))(mixin("_value" ~ op ~ "other"));
    }

    // ditto
    auto opBinaryRight(string op, T)(T other) const
        if (isNumeric!T && op == "*")
    {
        return this * other;
    }

    // ditto
    auto opBinaryRight(string op, T)(T other) const
        if (isNumeric!T && op == "/")
    {
        static if (runtime)
            return RTQuantity(other / _value, dimensions.exp(-1));
        else
            return Quantity!(dimensions.exp(-1), N)(other / _value);
    }

    // Add/sub assign with a quantity that shares the same dimensions
    void opOpAssign(string op, T)(T other)
        if (isQuantity!T && (op == "+" || op == "-"))
    {
        mixin(checkDim!"other.dimensions");
        mixin("_value " ~ op ~ "= other._value;");
    }

    // Add/sub assign a scalar to a dimensionless quantity
    void opOpAssign(string op, T)(T other)
        if (isNumeric!T && (op == "+" || op == "-"))
    {
        mixin(checkDim!"Dimensions.init");
        mixin("_value " ~ op ~ "= other;");
    }
    
    // Mul/div assign with a dimensionless quantity
    void opOpAssign(string op, T)(T other)
        if (isQuantity!T && (op == "*" || op == "/"))
    {
        mixin(checkDim!"Dimensions.init");
        mixin("_value" ~ op ~ "= other._value;");
    }

    // Mul/div assign with a scalar factor
    void opOpAssign(string op, T)(T other)
        if (isNumeric!T && (op == "*" || op == "/"))
    {
        mixin("_value" ~ op ~ "= other;");
    }

    // Exact equality between quantities
    bool opEquals(T)(T other) const
        if (isQuantity!T)
    {
        mixin(checkDim!"other.dimensions");
        return _value == other._value;
    }

    // Exact equality between a dimensionless quantity and a scalar
    bool opEquals(T)(T other) const
        if (isNumeric!T)
    {
        mixin(checkDim!"Dimensions.init");
        return _value == other;
    }

    // Comparison between two quantities
    int opCmp(T)(T other) const
        if (isQuantity!T)
    {
        mixin(checkDim!"other.dimensions");
        if (_value == other._value)
            return 0;
        if (_value < other._value)
            return -1;
        return 1;
    }

    // Comparision between a dimensionless quantity and a scalar
    int opCmp(T)(T other) const
        if (isNumeric!T)
    {
        mixin(checkDim!"Dimensions.init");
        if (_value == other)
            return 0;
        if (_value < other)
            return -1;
        return 1;
    }

    void toString(scope void delegate(const(char)[]) sink) const
    {
        import std.format;
        formattedWrite(sink, "%s ", _value);
        sink(dimensions.toString);
    }
}

/// ditto
alias RTQuantity = Quantity!(null, real, AtRuntime.yes);

/// Tests whether T is a quantity type
template isQuantity(T)
{
    alias U = Unqual!T;
    static if (is(U _ : Quantity!X, X...))
        enum isQuantity = true;
    else
        enum isQuantity = false;
}

unittest // Quantity constructor
{
    enum time = Store!second(1 * minute);
    assert(time.value(second) == 60);
}

unittest // RTQuantity constructor
{
    RTQuantity time;
    time = RTQuantity(60, second.dimensions);
    assert(time.value(second) == 60);
}

unittest // Quantity.value
{
    enum speed = 100 * meter / (5 * second);
    static assert(speed.value(meter / second) == 20);
}

unittest // RTQuantity.value
{
    RTQuantity speed = 100 * meter / (5 * second);
    assert(speed.value(meter / second) == 20);
}

unittest // Quantity.store
{
    enum length = meter.store!real;
    static assert(is(length.valueType == real));
}

unittest // Quantity.opCast
{
    enum angle = 12 * radian;
    static assert(cast(double) angle == 12);
}

unittest // RTQuantity.opCast
{
    RTQuantity angle = 12 * radian;
    assert(cast(double) angle == 12);
}

unittest // Quantity.opAssign Q = Q
{
    auto length = meter;
    length = 2.54 * centi(meter);
    assert(length.value(meter).approxEqual(0.0254));
}

unittest // RTQuantity.opAssign Q = Q
{
    RTQuantity length;
    length = 2.54 * centi(meter);
    assert(length.value(meter).approxEqual(0.0254));
    length = RTQuantity(2.54 * centi(meter));
    assert(length.value(meter).approxEqual(0.0254));
}

unittest // Quantity.opUnary +Q -Q
{
    enum length = + meter;
    static assert(length == 1 * meter);
    enum length2 = - meter;
    static assert(length2 == -1 * meter);
}

unittest // RTQuantity.opUnary +Q -Q
{
    RTQuantity length = + meter;
    assert(length == 1 * meter);
    length = - meter;
    assert(length == -1 * meter);
}

unittest // Quantity.opBinary Q*N Q/N
{
    enum time = second * 60;
    static assert(time.value(second) == 60);
    enum time2 = second / 2;
    static assert(time2.value(second) == 1.0/2);
}

unittest // RTQuantity.opBinary Q*N Q/N
{
    RTQuantity time = second * 60;
    assert(time.value(second) == 60);
    time = second / 2;
    assert(time.value(second) == 1.0/2);
}

unittest // Quantity.opBinary Q+Q Q-Q
{
    enum length = meter + meter;
    static assert(length.value(meter) == 2);
    enum length2 = length - meter;
    static assert(length2.value(meter) == 1);
}

unittest // RTQuantity.opBinary Q+Q Q-Q
{
    RTQuantity length = meter + meter;
    assert(length.value(meter) == 2);
    length = length - meter;
    assert(length.value(meter) == 1);
}

unittest // Quantity.opBinary Q*Q Q/Q
{
    enum length = meter * 5;
    enum surface = length * length;
    static assert(surface.value(square(meter)) == 5*5);
    enum length2 = surface / length;
    static assert(length2.value(meter) == 5);

    enum x = minute / second;
    static assert(x.rawValue == 60);

    enum y = minute * hertz;
    static assert(y.rawValue == 60);
}

unittest // RTQuantity.opBinary Q*Q Q/Q
{
    RTQuantity length = meter * 5;
    RTQuantity surface = length * length;
    assert(surface.value(square(meter)) == 5*5);
    RTQuantity length2 = surface / length;
    assert(length2.value(meter) == 5);
    
    RTQuantity x = minute / second;
    assert(x.rawValue == 60);
    
    RTQuantity y = minute * hertz;
    assert(y.rawValue == 60);
}

unittest // Quantity.opBinaryRight N*Q
{
    enum length = 100 * meter;
    static assert(length == meter * 100);
}

unittest // RTQuantity.opBinaryRight N*Q
{
    RTQuantity length = 100 * meter;
    assert(length == meter * 100);
}

unittest // Quantity.opBinaryRight N/Q
{
    enum x = 1 / (2 * meter);
    static assert(x.value(1/meter) == 1.0/2);
}

unittest // RTQuantity.opBinaryRight N/Q
{
    RTQuantity x = 1 / (2 * meter);
    assert(x.value(1/meter) == 1.0/2);
}

unittest // Quantity.opOpAssign Q+=Q Q-=Q
{
    auto time = 10 * second;
    time += 50 * second;
    assert(time.value(second).approxEqual(60));
    time -= 40 * second;
    assert(time.value(second).approxEqual(20));
}

unittest // RTQuantity.opOpAssign Q+=Q Q-=Q
{
    RTQuantity time = 10 * second;
    time += 50 * second;
    assert(time.value(second).approxEqual(60));
    time -= 40 * second;
    assert(time.value(second).approxEqual(20));
}

unittest // Quantity.opOpAssign Q*=N Q/=N
{
    auto time = 20 * second;
    time *= 2;
    assert(time.value(second).approxEqual(40));
    time /= 4;
    assert(time.value(second).approxEqual(10));
}

unittest // RTQuantity.opOpAssign Q*=N Q/=N
{
    RTQuantity time = 20 * second;
    time *= 2;
    assert(time.value(second).approxEqual(40));
    time /= 4;
    assert(time.value(second).approxEqual(10));
}

unittest // Quantity.opEquals
{
    assert(1 * minute == 60 * second);
}

unittest // RTQuantity.opEquals
{
    assert(RTQuantity(1 * minute) == RTQuantity(60 * second));
}

unittest // Quantity.opCmp
{
    assert(second < minute);
    assert(minute <= minute);
    assert(hour > minute);
    assert(hour >= hour);
}

unittest // RTQuantity.opCmp
{
    assert(RTQuantity(second) < RTQuantity(minute));
    assert(RTQuantity(minute) <= RTQuantity(minute));
    assert(RTQuantity(hour) > RTQuantity(minute));
    assert(hour >= hour);
}

unittest // Compilation errors for incompatible dimensions
{
    static assert(!__traits(compiles, Store!meter(1 * second)));
    Store!meter m;
    static assert(!__traits(compiles, m.value(second)));
    static assert(!__traits(compiles, m = second));
    static assert(!__traits(compiles, m + second));
    static assert(!__traits(compiles, m - second));
    static assert(!__traits(compiles, m + 1));
    static assert(!__traits(compiles, m - 1));
    static assert(!__traits(compiles, 1 + m));
    static assert(!__traits(compiles, 1 - m));
    static assert(!__traits(compiles, m += second));
    static assert(!__traits(compiles, m -= second));
    static assert(!__traits(compiles, m *= second));
    static assert(!__traits(compiles, m /= second));
    static assert(!__traits(compiles, m *= meter));
    static assert(!__traits(compiles, m /= meter));
    static assert(!__traits(compiles, m += 1));
    static assert(!__traits(compiles, m -= 1));
    static assert(!__traits(compiles, m == 1));
    static assert(!__traits(compiles, m == second));
    static assert(!__traits(compiles, m < second));
    static assert(!__traits(compiles, m < 1));
}

unittest // Exceptions for incompatible dimensions
{
    RTQuantity m = meter;
    assertThrown!DimensionException(m = RTQuantity(1 * second));
    assertThrown!DimensionException(m.value(second));
    assertThrown!DimensionException(m = second);
    assertThrown!DimensionException(m + second);
    assertThrown!DimensionException(m - second);
    assertThrown!DimensionException(m + 1);
    assertThrown!DimensionException(m - 1);
    assertThrown!DimensionException(1 + m);
    assertThrown!DimensionException(1 - m);
    assertThrown!DimensionException(m += second);
    assertThrown!DimensionException(m -= second);
    assertThrown!DimensionException(m *= second);
    assertThrown!DimensionException(m /= second);
    assertThrown!DimensionException(m *= meter);
    assertThrown!DimensionException(m /= meter);
    assertThrown!DimensionException(m += 1);
    assertThrown!DimensionException(m -= 1);
    assertThrown!DimensionException(m == 1);
    assertThrown!DimensionException(m == second);
    assertThrown!DimensionException(m < second);
    assertThrown!DimensionException(m < 1);
}

unittest // immutable Quantity
{
    immutable length = 3e5 * kilo(meter);
    immutable time = 1 * second;
    immutable speedOfLight = length / time;
    assert(speedOfLight == 3e5 * kilo(meter) / second);
    assert(speedOfLight > 1 * meter / minute);
}

unittest // immutable RTQuantity
{
    immutable RTQuantity length = 3e5 * kilo(meter);
    immutable RTQuantity time = 1 * second;
    immutable RTQuantity speedOfLight = length / time;
    assert(speedOfLight == 3e5 * kilo(meter) / second);
    assert(speedOfLight > 1 * meter / minute);
}

/// Creates a new monodimensional unit.
template unit(string name, string symbol = name, N = double)
{
    enum unit = Quantity!(Dimensions(name, symbol), N)(1.0);
}
///
@name(`unit!"dim"`)
unittest
{
    enum euro = unit!"currency";
    static assert(isQuantity!(typeof(euro)));
    enum dollar = euro / 1.35;
    assert((1.35 * dollar).value(euro).approxEqual(1));
}

/++
Utility templates to create quantity types. The unit is only used to set the
dimensions, it doesn't bind the stored value to a particular unit. Use in 
conjunction with the store method of quantities.
+/
template Store(Q, N = double)
    if (isQuantity!Q)
{
    alias Store = Quantity!(Q.dimensions, N);
}

/// ditto
template Store(alias unit, N = double)
    if (isQuantity!(typeof(unit)))
{
    alias Store = Quantity!(unit.dimensions, N);
}

///
unittest // Store example
{
    alias Mass = Store!kilogram;
    Mass mass = 15 * ton;
    
    alias Surface = Store!(square(meter), float);
    assert(is(Surface.valueType == float));
    Surface s = 4 * square(meter);
}

unittest // Type conservation
{
    Store!(meter, float) length; 
    Store!(second, double) time;
    Store!(meter/second, real) speed;
    length = 1 * kilo(meter);
    time = 2 * hour;
    speed = length / time;
    assert(is(speed.valueType == real));
}

/++
This struct holds a representation the dimensions of a quantity/unit.
+/
struct Dimensions
{
    private static struct Dim
    {
        int power;
        string symbol;
    }

    private Dim[string] dims;

    package this(string name, string symbol = null) pure
    {
        if (!name.length)
            throw new Exception("The name of a dimension cannot be empty");
        if (!symbol.length)
            symbol = name;

        dims[name] = Dim(1, symbol);
    }

    package immutable(Dimensions) idup() const pure
    {
        Dimensions result;
        foreach (k, v; dims)
            result.dims[k] = v;
        return cast(immutable) result;
    }

    /// Tests if the dimensions are empty
    @property bool empty() const pure nothrow
    {
        return dims.length == 0;
    }
    
    package Dimensions opBinary(string op)(const(Dimensions) other) const pure
    {
        static assert(op == "*" || op == "/", "Unsupported dimension operator: " ~ op);

        Dimensions result;
        foreach (k, v; dims)
            result.dims[k] = Dim(v.power, v.symbol);
        foreach (k; other.dims.keys)
        {
            enum powop = op == "*" ? "+" : "-";
            if (k in dims)
            {
                auto p = mixin("dims[k].power" ~ powop ~ "other.dims[k].power");
                if (p == 0)
                    result.dims.remove(k);
                else
                    result.dims[k] = Dim(p, other.dims[k].symbol);
            }
            else
                result.dims[k] = Dim(mixin(powop ~ "other.dims[k].power"), other.dims[k].symbol);
        }
        return result;
    }
    
    package Dimensions exp(int value) const pure
    {
        if (value == 0)
            return Dimensions.init;

        Dimensions result;
        foreach (k; dims.keys)
            result.dims[k] = Dim(dims[k].power * value, dims[k].symbol);
        return result;
    }

    package Dimensions expInv(int value) const pure
    {
        assert(value > 0, "Bug: using Dimensions.expInv with a value <= 0");
        
        Dimensions result;
        foreach (k; dims.keys)
        {
            enforce(dims[k].power % value == 0, "Operation results in a non-integral dimension");
            result.dims[k] = Dim(dims[k].power / value, dims[k].symbol);
        }
        return result;
    }

    /// Returns true if the dimensions are the same
    bool opEquals(const(Dimensions) other) const
    {
        import std.algorithm : sort, equal;
        
        bool same = (dims.keys.length == other.dims.keys.length)
            && (sort(dims.keys).equal(sort(other.dims.keys)));
        if (!same)
            return false;
        
        foreach (k, v; dims)
        {
            auto ov = k in other.dims;
            assert(ov);
            if (v.power != ov.power)
            {
                same = false;
                break;
            }
        }
        return same;
    }
    
    string toString(bool complete = false) const pure
    {
        import std.algorithm : filter;
        import std.array : join;
        import std.conv : to;
        
        static string stringize(string base, int power)
        {
            if (power == 0)
                return null;
            if (power == 1)
                return base;
            return base ~ "^" ~ to!string(power);
        }
        
        string[] dimstrs;
        foreach (k, v; dims)
            dimstrs ~= stringize(v.symbol, v.power);
        
        string result = dimstrs.filter!"a !is null".join(" ");
        if (!result.length)
            return complete ? "scalar" : "";
        
        return result;
    }
}

unittest // Dimension
{
    import std.exception;

    enum test = Dimensions(SI.length) * Dimensions(SI.mass);
    assert(collectException(test.expInv(2)));

    enum d = Dimensions("foo");
    enum e = Dimensions("bar");
    enum f = Dimensions("bar");
    static assert(e == f);
    enum g = test.exp(-1);
    static assert(g.exp(-1) == test);
    enum i = test * test;
    static assert(i == test.exp(2));
    enum j = test / test;
    static assert(j.empty);
    static assert(j.toString == "");
    enum k = i.expInv(2);
    static assert(k == test);
    static assert(d * e == e * d);

    enum m = Dimensions("mdim", "m");
    enum n = Dimensions("ndim", "n");
    static assert(m.toString == "m");
    static assert(m.exp(2).toString == "m^2");
    static assert(m.exp(-1).toString == "m^-1");
    static assert((m*m).expInv(2).toString == "m");
    static assert((m*n).toString == "m n" || (m*n).toString == "n m");
}

/// Exception thrown when operating on two units that are not interconvertible.
class DimensionException : Exception
{
    @safe pure nothrow
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        super(msg, file, line, next);
    }
    
    @safe pure nothrow
    this(string msg, Throwable next, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line, next);
    }
}



