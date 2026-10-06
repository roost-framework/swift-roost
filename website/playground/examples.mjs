// Guided Swift samples. The browser reads supported values; it does not compile Swift.
export const examples = [
  {
    id: "counter",
    name: "Counter",
    filename: "Counter.swift",
    hint: "Change the starting value in mount, the amount added in handleEvent, or the heading and button text inside #live.",
    supported:
      "the starting integer, increment amount, heading, description, and button label",
    template:
      'import RoostPlayground\n\n@main\nstruct Counter: LivePlayground {\n    func mount(_ context: LiveContext) async throws -> Int { «start» }\n\n    func handleEvent(_ event: LiveEvent, state: Int) async throws -> Int {\n        guard event.name == "increment" else { throw LiveError.invalidEvent }\n        return state + «step»\n    }\n\n    // swiftformat:disable:next unusedArguments\n    func render(_ count: Int) -> ESWLiveRender {\n        #live("""\n        <main>\n          <h1>«heading»</h1>\n          <p>«description»</p>\n          <output>{count}</output>\n          <button type="button" esw-click="increment">«button»</button>\n        </main>\n        """)\n    }\n}\n',
    fields: {
      start: {
        kind: "integer",
        initial: "0",
        label: "Starting value",
      },
      step: {
        kind: "integer",
        initial: "1",
        label: "Increment amount",
      },
      heading: {
        kind: "htmlText",
        initial: "A little Swift, live.",
        label: "Heading",
      },
      description: {
        kind: "htmlText",
        initial: "Good ideas start with a small change.",
        label: "Description",
      },
      button: {
        kind: "htmlText",
        initial: "+1",
        label: "Button label",
      },
    },
  },
  {
    id: "greeting",
    name: "Greeting",
    filename: "Greeting.swift",
    hint: "Change the initial greeting, the words around \\(name), or the heading, input label, and button text. Then submit a name in the preview.",
    supported:
      "the initial greeting, greeting prefix and suffix, heading, input label, and button label",
    template:
      'import RoostPlayground\n\n@main\nstruct Greeting: LivePlayground {\n    func mount(_ context: LiveContext) async throws -> String {\n        "«initial»"\n    }\n\n    func handleEvent(_ event: LiveEvent, state: String) async throws -> String {\n        guard event.name == "greet" else { throw LiveError.invalidEvent }\n        let name = event.value("name") ?? ""\n        return "«prefix»\\(name)«suffix»"\n    }\n\n    // swiftformat:disable:next unusedArguments\n    func render(_ greeting: String) -> ESWLiveRender {\n        #live("""\n        <main>\n          <h1>«heading»</h1>\n          <form esw-submit="greet">\n            <label for="name">«label»</label>\n            <input id="name" name="name" autocomplete="off" />\n            <button type="submit">«button»</button>\n          </form>\n          <p>{greeting}</p>\n        </main>\n        """)\n    }\n}\n',
    fields: {
      initial: {
        kind: "swiftString",
        initial: "Your next interaction starts here.",
        label: "Initial greeting",
      },
      prefix: {
        kind: "swiftString",
        initial: "Hello, ",
        label: "Greeting prefix",
      },
      suffix: {
        kind: "swiftString",
        initial: "!",
        label: "Greeting suffix",
      },
      heading: {
        kind: "htmlText",
        initial: "Make yourself at home.",
        label: "Heading",
      },
      label: {
        kind: "htmlText",
        initial: "Your name",
        label: "Input label",
      },
      button: {
        kind: "htmlText",
        initial: "Say hello",
        label: "Button label",
      },
    },
  },
  {
    id: "toggle",
    name: "Toggle",
    filename: "Toggle.swift",
    hint: "Change false to true in mount, or edit the heading and button label. The button flips the Boolean state.",
    supported: "the initial Boolean, heading, description, and button label",
    template:
      'import RoostPlayground\n\n@main\nstruct Toggle: LivePlayground {\n    func mount(_ context: LiveContext) async throws -> Bool { «enabled» }\n\n    func handleEvent(_ event: LiveEvent, state: Bool) async throws -> Bool {\n        guard event.name == "toggle" else { throw LiveError.invalidEvent }\n        return !state\n    }\n\n    // swiftformat:disable:next unusedArguments\n    func render(_ enabled: Bool) -> ESWLiveRender {\n        #live("""\n        <main>\n          <h1>«heading»</h1>\n          <p>«description»</p>\n          <output>{enabled ? "On" : "Off"}</output>\n          <button type="button" esw-click="toggle">«button»</button>\n        </main>\n        """)\n    }\n}\n',
    fields: {
      enabled: {
        kind: "boolean",
        initial: "false",
        label: "Initial state",
      },
      heading: {
        kind: "htmlText",
        initial: "A change of state.",
        label: "Heading",
      },
      description: {
        kind: "htmlText",
        initial: "Small interactions, written in Swift.",
        label: "Description",
      },
      button: {
        kind: "htmlText",
        initial: "Switch it up",
        label: "Button label",
      },
    },
  },
];

export const initialSource = (example) =>
  example.template.replace(/«(\w+)»/g, (_, key) => example.fields[key].initial);
const escapeRegExp = (text) => text.replace(/[.*+?^{}()|[\]\\$]/g, "\\$&");
const matchers = new Map(
  examples.map((example) => {
    const keys = [];
    const pattern = example.template
      .split(/(«\w+»)/)
      .map((part) => {
        if (part.startsWith("«") && part.endsWith("»")) {
          keys.push(part.slice(1, -1));
          return "([\\s\\S]*?)";
        }
        return escapeRegExp(part);
      })
      .join("");
    return [example.id, { regex: new RegExp("^" + pattern + "$"), keys }];
  }),
);

export function readExample(example, source) {
  if (source.length > 16000)
    return { error: "Keep this example under 16,000 characters." };
  const matcher = matchers.get(example.id);
  const match = matcher.regex.exec(source.replace(/\r\n/g, "\n"));
  if (!match)
    return {
      error:
        "This guided lesson supports changes to " +
        example.supported +
        ". Keep the surrounding Swift and template structure as shown, or reset the example. To change the program itself, download it and use the local Roost Playground.",
    };
  const values = {};
  for (const [index, key] of matcher.keys.entries()) {
    const field = example.fields[key];
    const value = match[index + 1];
    if (field.kind === "integer") {
      if (
        !/^-?\d+$/.test(value) ||
        !Number.isSafeInteger(Number(value)) ||
        Math.abs(Number(value)) > 1000000
      )
        return {
          error:
            field.label + ": use a whole number from -1,000,000 to 1,000,000.",
        };
      values[key] = Number(value);
    } else if (field.kind === "boolean") {
      if (!["true", "false"].includes(value))
        return { error: field.label + ": use true or false." };
      values[key] = value === "true";
    } else {
      const forbidden =
        field.kind === "htmlText"
          ? /[<>&{}\\"«»\r\n\u0000-\u001f\u007f]/u
          : /[\\"«»\r\n\u0000-\u001f\u007f]/u;
      if (
        forbidden.test(value) ||
        value.length > 160 ||
        (field.kind === "htmlText" && !value.trim())
      )
        return {
          error:
            field.label +
            ": use " +
            (field.kind === "htmlText"
              ? "plain text without HTML, template expressions, quotes, or backslashes"
              : "text without quotes, escapes, or line breaks") +
            ", up to 160 characters.",
        };
      values[key] = value;
    }
  }
  return { values };
}

export function editableRanges(example, source) {
  if (source.length > 16000) return [];
  const match = matchers.get(example.id).regex.exec(source);
  if (!match) return [];
  const ranges = [];
  let cursor = 0;
  let capture = 1;
  for (const part of example.template.split(/(«\w+»)/)) {
    if (part.startsWith("«") && part.endsWith("»")) {
      const key = part.slice(1, -1);
      const end = cursor + match[capture++].length;
      ranges.push({
        key,
        label: example.fields[key].label,
        start: cursor,
        end,
      });
      cursor = end;
    } else {
      cursor += part.length;
    }
  }
  return ranges;
}
