// Progressive enhancements. The framework overview and code stay readable without JS.
const announcement = document.querySelector("#site-announcement");
document.querySelectorAll("[data-copy]").forEach((button) => {
  button.hidden = false;
  const original = button.innerHTML;
  let resetTimer;
  button.addEventListener("click", async () => {
    const code = document.getElementById(button.dataset.copy);
    try {
      await navigator.clipboard.writeText(code.textContent);
      button.textContent = "Copied ✓";
      announcement.textContent = "Code copied to clipboard.";
    } catch {
      const range = document.createRange();
      range.selectNodeContents(code);
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      button.textContent = "Selected";
      announcement.textContent =
        "Copy is unavailable. The code is selected; use your keyboard to copy it.";
    }
    clearTimeout(resetTimer);
    resetTimer = setTimeout(() => {
      button.innerHTML = original;
    }, 2200);
  });
});

const tabs = [...document.querySelectorAll("[data-panel]")];
const panels = [...document.querySelectorAll(".tour-panel")];
document.querySelector(".tour-tabs").setAttribute("role", "tablist");
tabs.forEach((tab, index) => {
  tab.id = `tour-tab-${index}`;
  tab.setAttribute("role", "tab");
  tab.setAttribute("aria-controls", tab.dataset.panel);
  const panel = document.getElementById(tab.dataset.panel);
  panel.setAttribute("role", "tabpanel");
  panel.setAttribute("aria-labelledby", tab.id);
  tab.addEventListener("click", (event) => {
    event.preventDefault();
    selectTab(index);
  });
  tab.addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = (index + 1) % tabs.length;
    if (event.key === "ArrowLeft")
      next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = tabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectTab(next);
      tabs[next].focus();
    }
  });
});
function selectTab(index) {
  tabs.forEach((tab, i) => {
    tab.setAttribute("aria-selected", String(index === i));
    tab.tabIndex = index === i ? 0 : -1;
  });
  panels.forEach((panel, i) => {
    panel.hidden = i !== index;
  });
}
const linkedTab = tabs.findIndex(
  (tab) => `#${tab.dataset.panel}` === location.hash,
);
selectTab(linkedTab >= 0 ? linkedTab : 0);
window.addEventListener("hashchange", () => {
  const index = tabs.findIndex(
    (tab) => `#${tab.dataset.panel}` === location.hash,
  );
  if (index >= 0) selectTab(index);
});

const initialLinks = [
  {
    title: "A tour of Swift",
    url: "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/guidedtour/",
    read: false,
  },
  {
    title: "Designing with contexts",
    url: "https://hexdocs.pm/phoenix/contexts.html",
    read: false,
  },
  {
    title: "The ESW template compiler",
    url: "https://github.com/Spectro-ORM/ESW",
    read: false,
  },
  {
    title: "Meet Roost",
    url: "https://github.com/Maartz/swift-roost",
    read: true,
  },
];
let links = initialLinks.map((link, id) => ({ ...link, id }));
let currentFilter = "unread";
let nextID = links.length;
const list = document.querySelector("#reading-list");
const queueStatus = document.querySelector("#queue-status");
const filters = [...document.querySelectorAll("[data-filter]")];
filters.forEach((button) => {
  button.disabled = false;
  button.addEventListener("click", () => {
    currentFilter = button.dataset.filter;
    renderQueue();
  });
});

function renderQueue(message) {
  filters.forEach((button) =>
    button.setAttribute(
      "aria-pressed",
      String(button.dataset.filter === currentFilter),
    ),
  );
  const unread = links.filter((link) => !link.read).length;
  const counts = { unread, read: links.length - unread, all: links.length };
  document.querySelectorAll("[data-count]").forEach((count) => {
    count.textContent = counts[count.dataset.count];
  });
  const visible = links.filter(
    (link) =>
      currentFilter === "all" ||
      (currentFilter === "read" ? link.read : !link.read),
  );
  list.replaceChildren();
  visible.forEach((link) => {
    const item = document.createElement("li");
    const toggle = document.createElement("button");
    toggle.type = "button";
    toggle.className = "reading-circle";
    toggle.dataset.linkId = link.id;
    toggle.setAttribute("aria-pressed", String(link.read));
    toggle.setAttribute(
      "aria-label",
      `${link.read ? "Mark as unread" : "Mark as finished"}: ${link.title}`,
    );
    toggle.textContent = link.read ? "✓" : "";
    toggle.addEventListener("click", () => {
      const oldIndex = visible.findIndex((entry) => entry.id === link.id);
      link.read = !link.read;
      renderQueue(
        `${link.title} ${link.read ? "moved to Finished." : "moved to To read."}`,
      );
      const remaining = [...list.querySelectorAll("button")];
      const replacement =
        remaining.find((button) => Number(button.dataset.linkId) === link.id) ||
        remaining[Math.min(oldIndex, remaining.length - 1)];
      (
        replacement ||
        filters.find((button) => button.dataset.filter === currentFilter)
      ).focus({ preventScroll: true });
    });
    const info = document.createElement("div");
    const title = document.createElement("a");
    title.className = "reading-title";
    title.textContent = link.title;
    title.href = link.url;
    title.target = "_blank";
    title.rel = "noopener noreferrer";
    title.setAttribute("aria-label", `${link.title} (opens in a new tab)`);
    const domain = document.createElement("span");
    domain.className = "reading-domain";
    domain.textContent = new URL(link.url).hostname.replace(/^www\./, "");
    const arrow = document.createElement("span");
    arrow.className = "reading-arrow";
    arrow.setAttribute("aria-hidden", "true");
    arrow.textContent = "↗";
    info.append(title, domain);
    item.append(toggle, info, arrow);
    list.append(item);
  });
  if (!visible.length) {
    const empty = document.createElement("li");
    empty.className = "empty-queue";
    empty.textContent =
      currentFilter === "read"
        ? "Nothing finished yet. Mark a link as read to move it here."
        : "All caught up. Save something good for later.";
    list.append(empty);
  }
  queueStatus.textContent =
    message ||
    `${visible.length} ${visible.length === 1 ? "link" : "links"} ${currentFilter === "read" ? "finished." : currentFilter === "all" ? "in your collection." : "for later."}`;
}
renderQueue();

const dialog = document.querySelector("#link-dialog");
const form = document.querySelector("#link-form");
const addLink = document.querySelector("#add-link");
const titleInput = document.querySelector("#link-title");
const urlInput = document.querySelector("#link-url");
const formError = document.querySelector("#form-error");
addLink.hidden = false;
addLink.addEventListener("click", () => {
  form.reset();
  formError.textContent = "";
  dialog.showModal();
  titleInput.focus();
});
document
  .querySelector(".dialog-close")
  .addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (
    event.clientX < rect.left ||
    event.clientX > rect.right ||
    event.clientY < rect.top ||
    event.clientY > rect.bottom
  )
    dialog.close();
});
form.addEventListener("submit", (event) => {
  event.preventDefault();
  const title = titleInput.value.trim();
  if (!title) {
    formError.textContent = "Give this link a title.";
    titleInput.focus();
    return;
  }
  let url;
  try {
    url = new URL(urlInput.value.trim());
  } catch {
    /* handled below */
  }
  if (
    !url ||
    !["http:", "https:"].includes(url.protocol) ||
    !url.hostname ||
    url.username ||
    url.password
  ) {
    formError.textContent =
      "Enter a complete http:// or https:// link without login details.";
    urlInput.focus();
    return;
  }
  links.unshift({ title, url: url.href, read: false, id: nextID++ });
  currentFilter = "unread";
  renderQueue(`${title} saved for later.`);
  dialog.close();
});
const reset = document.querySelector("#reset-demo");
reset.hidden = false;
reset.addEventListener("click", () => {
  links = initialLinks.map((link, id) => ({ ...link, id }));
  nextID = links.length;
  currentFilter = "unread";
  renderQueue("Preview reset. Three good things for later.");
});
