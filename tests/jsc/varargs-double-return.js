// Regression test for the armv7 Darwin ABI bug in LLInt's checkpoint_osr_exit_from_inlined_call
// trampoline: a double returned to an inlined varargs call site (OSR exit at op_call_varargs
// checkpoint) came back with its 32-bit halves swapped (2.2250744e-308). Timing dependent:
// 150 fresh copies; before the fix 2-6 of them failed with the DFG on.
//   jsc --useDollarVM=true varargs-double-return.js -- apply|direct|single|call|callapply
// mode: "apply" (bar calls baz.apply(null, arguments)), "direct" (bar calls baz(a, b)), "single" (foo computes)
var mode = typeof arguments !== "undefined" && arguments[0] ? arguments[0] : "direct";
var copies = 150, bad = 0, samples = [];
for (var k = 0; k < copies; ++k) {
    var baz = new Function("a", "b", "return a + b * 2; // " + k);
    var bodies = { apply: "return baz.apply(null, arguments);", direct: "return baz(a, b);", single: "return a + b * 2;", call: "return baz(a, b);", callapply: "return baz.apply(null, [a, b]);" };
    if (mode == "call" || mode == "callapply")
        noInline(baz);
    var bar = new Function("baz", "return function bar(a, b) { " + bodies[mode] + " } // " + k)(baz);
    var foo = new Function("bar", "return function foo(a, b) { return bar(a, b); } // " + k)(bar);
    noInline(foo);
    var n = 2000 + 300 * (k % 20);
    for (var i = 0; i < n; ++i) {
        if (foo(7, 11) != 29)
            throw "loop";
    }
    var r = foo(5, 2147483646);
    if (r != 4294967297) {
        bad++;
        if (samples.length < 4)
            samples.push(k + ":" + n + ":" + r);
    }
}
print(mode + " bad " + bad + "/" + copies + " " + samples.join(" "));
