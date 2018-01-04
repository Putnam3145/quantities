module tests.more_tests;

import quantities;
import std.math : approxEqual;

@("qVariant")
unittest
{
    static assert(is(typeof(meter.qVariant) == QVariant!double));
    static assert(meter == unit!double("L"));
    static assert(QVariant!double(meter) == unit!double("L"));
}

@("QVariant/Quantity")
@safe pure unittest
{
    enum meterVariant = meter.qVariant;
    static assert(meterVariant.value(meter) == 1);
    static assert(meterVariant.isConsistentWith(meter));
    meterVariant = meter + (meter * meter) / meter;
    assert(meterVariant.value(meter) == 1);
    meterVariant += meter;
    meterVariant -= meter;
    assert(meterVariant.value(meter) == 1);
    meterVariant *= meter;
    meterVariant /= meter;
    assert(meterVariant.value(meter) == 1);
    static assert(meterVariant == meter);
    static assert(meterVariant < 2 * meter);

    auto secondVariant = (2 * second).qVariant;
    auto test = secondVariant + second;
    assert(test.value(second).approxEqual(3));
    test = second + secondVariant;
    assert(test.value(second).approxEqual(3));
    test = secondVariant - second;
    assert(test.value(second).approxEqual(1));
    test = second - secondVariant;
    assert(test.value(second).approxEqual(-1));
    test = second * secondVariant;
    assert(test.value(square(second)).approxEqual(2));
    test = secondVariant * second;
    assert(test.value(square(second)).approxEqual(2));
    test = second / secondVariant;
    assert(test.value(one).approxEqual(0.5));
    test = secondVariant / second;
    assert(test.value(one).approxEqual(2));
    test = secondVariant % second;
    assert(test.value(second).approxEqual(0));
    test = (4 * second) % secondVariant;
    assert(test.value(second).approxEqual(0));
}

@("Functions with QVariant parameters")
unittest
{
    static QVariant!double catc(QVariant!double deltaAbs, QVariant!double deltaTime = 1 * minute)
    out (result)
    {
        assert(result.isConsistentWith(katal / liter));
    }
    do
    {
        immutable epsilon = 6.3 * liter / milli(mole) / centi(meter);
        immutable totalVolume = 285 * micro(liter);
        immutable sampleVolume = 25 * micro(liter);
        immutable lightPath = 0.6 * centi(meter);
        return deltaAbs / deltaTime / (epsilon * lightPath) * totalVolume / sampleVolume;
    }

    assert(catc(0.031.qVariant).value(parseSI("µmol/min/L")).approxEqual(93.5));
}

@("Functions with Quantity parameters")
unittest
{
    static auto catc(Dimensionless deltaAbs, Time deltaTime = 1 * minute)
    {
        enum epsilon = 6.3 * liter / milli(mole) / centi(meter);
        enum totalVolume = 285 * micro(liter);
        enum sampleVolume = 25 * micro(liter);
        enum lightPath = 0.6 * centi(meter);
        return deltaAbs / deltaTime / (epsilon * lightPath) * totalVolume / sampleVolume;
    }

    static assert(catc(0.031 * one).value(si!"µmol/min/L").approxEqual(93.5));
}