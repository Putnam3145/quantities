module tests.fake_units_tests;

debug import std.stdio;

@("Let there be units")
unittest
{
    import quantities;
    import std.exception : assertThrown;

    // Let there be units
    auto apple = unit!int("Apple");
    auto cookie = unit!int("Cookie");
    auto movie = unit!int("Movie");

    // Let there be prefixes
    enum int few = 2;
    enum int many = 100;

    auto tolerated = few * cookie / movie;
    auto toxic = 50 * tolerated;

    // 100 cookies is really too much for one movie
    assert(toxic.value(cookie / movie) == 100);

    // How many cookies are tolerated if I watch 10 movies a week
    assert((tolerated * 10 * movie).value(cookie) == 20);

    // Don't mix cookies with apples
    assertThrown!DimensionException(cookie + apple);

    // Let there be a parser
    auto symbols = SymbolList!int().addUnit("🍎", apple).addUnit("🍪",
            cookie).addUnit("🎬", movie).addPrefix("🙂", few).addPrefix("😃", many);
    auto parser = Parser!int(symbols);

    // Use parsed quantities
    assert(tolerated == parser.parse("🙂🍪/🎬"));
    assert(toxic == parser.parse("😃🍪/🎬"));
}
