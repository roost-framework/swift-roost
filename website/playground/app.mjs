import {
  examples,
  initialSource,
  readExample,
  editableRanges,
} from "./examples.mjs";

const editor = document.querySelector("#source-editor");
const lineNumbers = document.querySelector("#line-numbers");
const position = document.querySelector("#editor-position");
const status = document.querySelector("#preview-status");
const preview = document.querySelector("#preview-root");
const previewMessage = document.querySelector("#preview-message");
const diagnostics = document.querySelector("#diagnostics");
const diagnosticDetail = document.querySelector("#diagnostic-detail");
const announcement = document.querySelector("#playground-announcement");
const filename = document.querySelector("#source-filename");
const tabs = [...document.querySelectorAll("[data-example]")];
const shortcuts = document.querySelector("#edit-shortcuts");
const drafts = new Map(
  examples.map((example) => [example.id, initialSource(example)]),
);
let selected = examples[0];
let lastRunSource;

function node(tag, text, className) {
  const element = document.createElement(tag);
  if (text !== undefined) element.textContent = text;
  if (className) element.className = className;
  return element;
}

function updateEditor() {
  lineNumbers.textContent = Array.from(
    { length: editor.value.split("\n").length },
    (_, i) => i + 1,
  ).join("\n");
  const before = editor.value.slice(0, editor.selectionStart).split("\n");
  position.textContent =
    "Line " + before.length + ", column " + (before.at(-1).length + 1);
  lineNumbers.style.setProperty("--editor-scroll", -editor.scrollTop + "px");
}

function sourceChanged() {
  drafts.set(selected.id, editor.value);
  updateEditor();
  const canJump = editableRanges(selected, editor.value).length > 0;
  for (const button of shortcuts.children) button.disabled = !canJump;
  if (editor.value !== lastRunSource) {
    status.textContent = "Edits to run";
    status.dataset.phase = "edited";
  } else {
    status.textContent = "Preview ready";
    status.dataset.phase = "ready";
  }
}

function renderShortcuts() {
  shortcuts.replaceChildren();
  for (const [key, field] of Object.entries(selected.fields)) {
    const button = node("button", field.label);
    button.type = "button";
    button.addEventListener("click", () => {
      const range = editableRanges(selected, editor.value).find(
        (range) => range.key === key,
      );
      if (!range) return;
      editor.focus();
      editor.setSelectionRange(range.start, range.end);
      const line = editor.value.slice(0, range.start).split("\n").length - 1;
      const lineHeight = parseFloat(getComputedStyle(editor).lineHeight);
      editor.scrollTop = Math.max(
        0,
        line * lineHeight - editor.clientHeight / 3,
      );
      editor.scrollLeft = 0;
      updateEditor();
      announcement.textContent =
        field.label + " selected. Type to replace it, then run the example.";
    });
    button.disabled = editableRanges(selected, editor.value).length === 0;
    shortcuts.append(button);
  }
}

function renderPreview(example, values) {
  preview.replaceChildren();
  previewMessage.textContent =
    "Browser preview · state resets when you run an example.";
  const brand = node("div", undefined, "brand");
  brand.setAttribute("aria-hidden", "true");
  const mark = node("img");
  mark.src = "assets/roost-mark.png";
  mark.alt = "";
  mark.width = 32;
  mark.height = 32;
  const word = node("span", "roost");
  word.append(node("span", ".", "orange"));
  brand.append(mark, word);
  preview.append(
    brand,
    node("p", example.name.toUpperCase(), "eyebrow"),
    node("h2", values.heading),
  );
  if (values.description !== undefined)
    preview.append(node("p", values.description));

  if (example.id === "counter") {
    let count = values.start;
    const row = node("div", undefined, "preview-counter");
    const output = node("output", count);
    output.setAttribute("aria-label", "Counter value");
    output.setAttribute("aria-live", "polite");
    const button = node("button", values.button, "button");
    button.type = "button";
    button.addEventListener("click", () => {
      const next = count + values.step;
      if (!Number.isSafeInteger(next)) {
        previewMessage.textContent =
          "The browser preview reached its safe integer limit. Run the example to reset it.";
        return;
      }
      count = next;
      output.textContent = count;
      previewMessage.textContent = "increment → " + count;
    });
    row.append(output, button);
    preview.append(row);
  } else if (example.id === "greeting") {
    const form = node("form", undefined, "preview-form");
    const label = node("label", values.label);
    label.htmlFor = "preview-name";
    const input = node("input");
    input.id = "preview-name";
    input.name = "name";
    input.autocomplete = "off";
    input.placeholder = "Ada";
    const row = node("div");
    const button = node("button", values.button, "button");
    button.type = "submit";
    const output = node("p", values.initial, "greeting-output");
    output.setAttribute("role", "status");
    output.setAttribute("aria-live", "polite");
    row.append(input, button);
    form.append(label, row);
    form.addEventListener("submit", (event) => {
      event.preventDefault();
      output.textContent = values.prefix + input.value + values.suffix;
      previewMessage.textContent = "greet → greeting updated";
    });
    preview.append(form, output);
  } else {
    let enabled = values.enabled;
    const row = node("div", undefined, "preview-toggle");
    const output = node("output", enabled ? "On" : "Off");
    output.setAttribute("aria-live", "polite");
    const button = node("button");
    button.type = "button";
    button.setAttribute("role", "switch");
    button.setAttribute("aria-label", values.button);
    button.setAttribute("aria-checked", String(enabled));
    const label = node("p", values.button);
    button.addEventListener("click", () => {
      enabled = !enabled;
      output.textContent = enabled ? "On" : "Off";
      button.setAttribute("aria-checked", String(enabled));
      previewMessage.textContent = "toggle → " + enabled;
    });
    row.append(button, label, output);
    preview.append(row);
  }
}

function runExample() {
  const result = readExample(selected, editor.value);
  if (result.error) {
    diagnosticDetail.textContent = result.error;
    diagnostics.hidden = false;
    status.textContent = "Check your edit";
    status.dataset.phase = "error";
    return false;
  }
  diagnostics.hidden = true;
  diagnosticDetail.textContent = "";
  renderPreview(selected, result.values);
  lastRunSource = editor.value;
  status.textContent = "Preview ready";
  status.dataset.phase = "ready";
  announcement.textContent = selected.name + " preview updated. State reset.";
  return true;
}

function selectExample(index) {
  selected = examples[index];
  tabs.forEach((tab, i) => {
    tab.setAttribute("aria-selected", String(i === index));
    tab.tabIndex = i === index ? 0 : -1;
  });
  document
    .querySelector("#editor-pane")
    .setAttribute("aria-labelledby", tabs[index].id);
  filename.textContent = selected.filename;
  document.querySelector("#lesson-instruction").textContent = selected.hint;
  editor.value = drafts.get(selected.id);
  editor.scrollTop = 0;
  editor.scrollLeft = 0;
  editor.setSelectionRange(0, 0);
  updateEditor();
  renderShortcuts();
  // An invalid saved draft still gets this lesson's default working preview.
  renderPreview(
    selected,
    readExample(selected, initialSource(selected)).values,
  );
  lastRunSource = initialSource(selected);
  runExample();
  const url = new URL(location.href);
  url.searchParams.set("example", selected.id);
  history.replaceState(null, "", url);
}

tabs.forEach((tab, index) => {
  tab.disabled = false;
  tab.addEventListener("click", () => selectExample(index));
  tab.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
    if (event.key === "ArrowLeft")
      next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = tabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectExample(next);
      tabs[next].focus();
    }
  });
});
editor.disabled = false;
editor.addEventListener("input", sourceChanged);
editor.addEventListener("scroll", updateEditor);
editor.addEventListener("click", updateEditor);
editor.addEventListener("keyup", updateEditor);
editor.addEventListener("keydown", (event) => {
  // Tab keeps its normal navigation behavior so keyboard users can leave the editor.
  if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
    event.preventDefault();
    runExample();
  }
});

const run = document.querySelector("#run-source");
run.disabled = false;
run.addEventListener("click", runExample);
const reset = document.querySelector("#reset-source");
reset.disabled = false;
reset.addEventListener("click", () => {
  drafts.set(selected.id, initialSource(selected));
  selectExample(examples.indexOf(selected));
  announcement.textContent = selected.name + " source and preview reset.";
});
const copy = document.querySelector("#copy-source");
copy.disabled = false;
let copyTimer;
copy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(editor.value);
    copy.textContent = "Copied ✓";
    announcement.textContent = "Swift source copied.";
  } catch {
    editor.focus();
    editor.select();
    copy.textContent = "Selected";
    announcement.textContent = "Source selected. Use your keyboard to copy it.";
  }
  clearTimeout(copyTimer);
  copyTimer = setTimeout(() => {
    copy.textContent = "Copy";
  }, 2200);
});
const download = document.querySelector("#download-source");
download.disabled = false;
download.addEventListener("click", () => {
  const url = URL.createObjectURL(
    new Blob([editor.value], { type: "text/plain;charset=utf-8" }),
  );
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = selected.filename;
  anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  announcement.textContent = selected.filename + " downloaded.";
});

const requested = new URLSearchParams(location.search).get("example");
selectExample(
  Math.max(
    0,
    examples.findIndex((example) => example.id === requested),
  ),
);
