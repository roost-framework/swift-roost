import test from "node:test";
import assert from "node:assert/strict";
import {
  examples,
  initialSource,
  readExample,
  editableRanges,
} from "./examples.mjs";

const [counter, greeting, toggle] = examples;
const sourceWith = (example, changes) =>
  example.template.replace(
    /«(\w+)»/g,
    (_, key) => changes[key] ?? example.fields[key].initial,
  );

test("supported edits update numeric, text, greeting, and Boolean values", () => {
  assert.deepEqual(
    readExample(
      counter,
      sourceWith(counter, {
        start: "-10",
        step: "2",
        heading: "Bonjour, Roost.",
        description: "A new idea.",
        button: "Add two",
      }),
    ).values,
    {
      start: -10,
      step: 2,
      heading: "Bonjour, Roost.",
      description: "A new idea.",
      button: "Add two",
    },
  );
  const result = readExample(
    greeting,
    sourceWith(greeting, { initial: "", prefix: "Welcome, ", suffix: " 🪺" }),
  );
  assert.equal(result.values.initial, "");
  assert.equal(result.values.prefix, "Welcome, ");
  assert.equal(result.values.suffix, " 🪺");
  assert.equal(
    readExample(toggle, sourceWith(toggle, { enabled: "true" })).values.enabled,
    true,
  );
});

test("downloaded samples round-trip through CRLF line endings", () => {
  for (const example of examples) {
    assert.deepEqual(
      readExample(example, initialSource(example).replace(/\n/g, "\r\n")),
      readExample(example, initialSource(example)),
    );
  }
});

test("changed Swift logic, event wiring, and template structure are rejected", () => {
  const source = initialSource(counter);
  for (const changed of [
    source.replace("return state + 1", "return state * 2"),
    source.replace('esw-click="increment"', 'esw-click="other"'),
    source.replace("<output>{count}</output>", "<output>{count * 2}</output>"),
    source + 'print("extra code")',
  ])
    assert.match(
      readExample(counter, changed).error,
      /guided lesson supports changes/,
    );
});

test("integer parsing rejects expressions, decimals, and unsafe values", () => {
  for (const value of [
    "1 + 1",
    "1.5",
    "NaN",
    "Infinity",
    "1000001",
    "-1000001",
    "9007199254740993",
    "",
    " 1",
  ]) {
    assert.match(
      readExample(counter, sourceWith(counter, { step: value })).error,
      /Increment amount/,
    );
  }
  for (const value of ["-1000000", "0", "1000000"]) {
    assert.equal(
      readExample(counter, sourceWith(counter, { start: value })).values.start,
      Number(value),
    );
  }
});

test("Boolean parsing accepts only Swift true and false literals", () => {
  for (const value of ["1", "TRUE", "!false", "false || true"]) {
    assert.match(
      readExample(toggle, sourceWith(toggle, { enabled: value })).error,
      /Initial state/,
    );
  }
});

test("template fields reject HTML, interpolation, and malformed Swift literals", () => {
  for (const value of [
    "<script>alert(1)</script>",
    "{count}",
    "&copy;",
    'a"b',
    "a\\b",
    "a\nb",
    "",
  ]) {
    assert.ok(
      readExample(counter, sourceWith(counter, { heading: value })).error,
      value,
    );
  }
  for (const value of ["\\(name)", '" + name + "', "line\nbreak", "\u0000"]) {
    assert.ok(
      readExample(greeting, sourceWith(greeting, { prefix: value })).error,
      value,
    );
  }
  assert.equal(
    readExample(greeting, sourceWith(greeting, { prefix: "<Ada> " })).values
      .prefix,
    "<Ada> ",
  );
});

test("field and source size limits return guidance", () => {
  assert.match(
    readExample(counter, sourceWith(counter, { heading: "a".repeat(161) }))
      .error,
    /160 characters/,
  );
  assert.match(readExample(counter, "a".repeat(16001)).error, /16,000/);
});

test("jump ranges follow edited values, including empty strings and Unicode", () => {
  const source = sourceWith(greeting, {
    initial: "",
    prefix: "Bonjour 🪺, ",
    heading: "Bienvenue.",
  });
  const ranges = editableRanges(greeting, source);
  assert.equal(ranges.length, 6);
  for (const range of ranges) {
    assert.equal(
      source.slice(range.start, range.end),
      readExample(greeting, source).values[range.key],
    );
  }
  assert.deepEqual(
    editableRanges(
      counter,
      initialSource(counter).replace("return state +", "return state *"),
    ),
    [],
  );
});
