"use strict";
const $ = (id) => document.getElementById(id);
let theme,
  baseline,
  schema,
  presets = [],
  local = false,
  native = false,
  noticeTimer;
const token = new URLSearchParams(location.hash.slice(1)).get("token") || "";
if (token) history.replaceState(null, "", location.pathname + location.search);
const clone = (v) => JSON.parse(JSON.stringify(v));
const colorFields = [
  [
    "Browser frame",
    "frame",
    [
      ["color", "Start"],
      ["endColor", "Finish"],
    ],
  ],
  [
    "Command palette",
    "palette",
    [
      ["color", "Background"],
      ["endColor", "Gradient"],
      ["accent", "Selection"],
      ["accentText", "Selected text"],
      ["text", "Text"],
      ["muted", "Secondary text"],
      ["border", "Border"],
    ],
  ],
];
const ranges = [
  ["frame", "inset", "Page inset", "pt"],
  ["frame", "radius", "Page corners", "pt"],
  ["frame", "angle", "Frame gradient", "°"],
  ["palette", "radius", "Palette corners", "pt"],
  ["palette", "rowRadius", "Selection corners", "pt"],
  ["palette", "width", "Palette width", "pt"],
  ["palette", "rowHeight", "Row height", "pt"],
  ["palette", "fontSize", "Text size", "pt"],
];

function message(text) {
  $("message").textContent = text;
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => {
    $("message").textContent = "";
  }, 6500);
}

function validate(value, rule, path = "theme") {
  const t = rule.type;
  if (
    (t === "object" &&
      (!value || typeof value !== "object" || Array.isArray(value))) ||
    (t === "string" && typeof value !== "string") ||
    (t === "boolean" && typeof value !== "boolean") ||
    ((t === "number" || t === "integer") &&
      (typeof value !== "number" || !Number.isFinite(value))) ||
    (t === "integer" && !Number.isInteger(value))
  )
    throw Error(`${path} must be ${t}`);
  if ("const" in rule && value !== rule.const)
    throw Error(`${path} must be ${rule.const}`);
  if (rule.enum && !rule.enum.includes(value))
    throw Error(`${path}: choose ${rule.enum.join(" or ")}`);
  if (t === "object") {
    for (const key of rule.required || [])
      if (!Object.prototype.hasOwnProperty.call(value, key))
        throw Error(`${path}.${key} is required`);
    for (const [key, item] of Object.entries(value)) {
      if (!Object.prototype.hasOwnProperty.call(rule.properties, key))
        throw Error(`${path}.${key} is not a supported setting`);
      validate(item, rule.properties[key], `${path}.${key}`);
    }
  }
  if (t === "string") {
    if (
      value.length < (rule.minLength || 0) ||
      value.length > (rule.maxLength || 10000)
    )
      throw Error(`${path} has an invalid length`);
    if (rule.pattern && value.match(new RegExp(rule.pattern))?.[0] !== value)
      throw Error(`${path} has an invalid format`);
  }
  if (
    (t === "number" || t === "integer") &&
    (value < (rule.minimum ?? -Infinity) || value > (rule.maximum ?? Infinity))
  )
    throw Error(`${path} is outside the supported range`);
}

function render() {
  const f = theme.frame,
    p = theme.palette;
  $("preview-window").style.background =
    `linear-gradient(${90 - f.angle}deg,${f.color},${f.endColor})`;
  $("preview-window").style.padding = `${f.inset}px`;
  document.querySelector(".preview-page").style.borderRadius = `${f.radius}px`;
  $("browser-controls").hidden = theme.controls.hidden;
  const panel = $("palette");
  Object.assign(panel.style, {
    background: `linear-gradient(${90 - p.angle}deg,${p.color},${p.endColor})`,
    borderColor: p.border,
    borderRadius: `${p.radius}px`,
    maxWidth: `${p.width}px`,
    width: `${Math.min(96, (88 * p.width) / 640)}%`,
    color: p.text,
  });
  document.querySelector(".palette-input").style.color = p.muted;
  document.querySelector(".palette-input>span").style.color = p.text;
  document.querySelector(".palette-divider").style.background = p.border;
  document.querySelectorAll(".palette-row").forEach((row) => {
    const selected = row.classList.contains("selected");
    Object.assign(row.style, {
      background: selected ? p.accent : "transparent",
      color: selected ? p.accentText : p.text,
      borderRadius: `${p.rowRadius}px`,
      height: `${p.rowHeight * 0.78}px`,
      fontSize: `${p.fontSize * 0.76}px`,
    });
    row.querySelector(".row-hint").style.color = selected
      ? p.accentText
      : p.muted;
  });
  $("theme-title").textContent = theme.name;
  $("theme-description").textContent = theme.description;
  $("appearance-badge").textContent = theme.appearance.toUpperCase();
  $("theme-name").value = theme.name;
  $("json-editor").value = JSON.stringify(theme, null, 2);
  document
    .querySelectorAll(".preset")
    .forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.id === baseline.id),
      ),
    );
}

function controls() {
  $("colors").replaceChildren();
  for (const [title, group, fields] of colorFields) {
    const heading = document.createElement("p");
    heading.className = "group-label";
    heading.textContent = title.toUpperCase();
    $("colors").append(heading);
    for (const [key, title] of fields) {
      const label = document.createElement("label");
      label.className = "color-control";
      const text = document.createElement("span");
      text.textContent = title;
      const wrap = document.createElement("span");
      wrap.className = "color-input";
      const hex = document.createElement("span");
      hex.className = "hex";
      hex.textContent = theme[group][key];
      const input = document.createElement("input");
      input.type = "color";
      input.value = theme[group][key];
      input.setAttribute("aria-label", `${group} ${title}`);
      input.addEventListener("input", () => {
        theme[group][key] = input.value.toUpperCase();
        hex.textContent = input.value;
        render();
      });
      wrap.append(hex, input);
      label.append(text, wrap);
      $("colors").append(label);
    }
  }
  $("shape").replaceChildren();
  for (const [group, key, title, unit] of ranges) {
    const rule = schema.properties[group].properties[key];
    const label = document.createElement("label");
    label.className = "range-control";
    const caption = document.createElement("span");
    caption.className = "range-caption";
    const text = document.createElement("span");
    text.textContent = title;
    const output = document.createElement("output");
    output.textContent = `${theme[group][key]}${unit}`;
    const input = document.createElement("input");
    input.type = "range";
    input.min = rule.minimum;
    input.max = rule.maximum;
    input.step = 1;
    input.value = theme[group][key];
    input.setAttribute("aria-label", title);
    input.addEventListener("input", () => {
      theme[group][key] = Number(input.value);
      output.textContent = `${input.value}${unit}`;
      render();
    });
    caption.append(text, output);
    label.append(caption, input);
    $("shape").append(label);
  }
  const label = document.createElement("label");
  label.className = "toggle-control";
  label.textContent = "Hide tabs & toolbar";
  const input = document.createElement("input");
  input.type = "checkbox";
  input.checked = theme.controls.hidden;
  input.addEventListener("change", () => {
    theme.controls.hidden = input.checked;
    render();
  });
  label.append(input);
  $("shape").append(label);
}

function select(value) {
  validate(value, schema);
  theme = clone(value);
  baseline = clone(value);
  controls();
  render();
}

async function readJSON(file) {
  const response = await fetch(file);
  if (!response.ok) throw Error(`Could not load ${file}`);
  return response.json();
}

async function boot() {
  schema = await readJSON("schema/theme.schema.json");
  const index = await readJSON("themes/index.json");
  presets = await Promise.all(
    index.map(({ id }) => readJSON(`themes/${id}.json`)),
  );
  for (const preset of presets) {
    validate(preset, schema);
    const button = document.createElement("button");
    button.className = "preset";
    button.dataset.id = preset.id;
    button.setAttribute("aria-pressed", "false");
    const swatch = document.createElement("span");
    swatch.className = "swatch";
    swatch.style.background = `linear-gradient(135deg,${preset.frame.color},${preset.frame.endColor})`;
    const text = document.createElement("span");
    const strong = document.createElement("strong");
    strong.textContent = preset.name;
    const small = document.createElement("small");
    small.textContent =
      preset.appearance === "light" ? "Light & warm" : "Dark & considered";
    text.append(strong, small);
    button.append(swatch, text);
    button.addEventListener("click", () => select(preset));
    $("theme-list").append(button);
  }
  select(presets[0]);
  if (token && location.hostname === "127.0.0.1") {
    try {
      const status = await readJSON("api/status");
      local = status.local;
      native = status.native;
      if (local) {
        $("connection").textContent = native
          ? "Native adapter installed"
          : "Local studio";
        $("apply").hidden = false;
        $("apply-note").textContent = native
          ? "Apply updates Polar automatically. No restart needed."
          : "Apply saves the theme. Install the native adapter to style Polar.";
        select(status.theme);
      }
    } catch {
      message(
        "Native connection unavailable. You can still preview and export themes.",
      );
    }
  }
}

$("theme-name").addEventListener("input", (e) => {
  theme.name = e.target.value;
  render();
});
$("reset").addEventListener("click", () => {
  select(baseline);
  message("Restored this theme’s starting point.");
});
$("toggle-palette").addEventListener("click", () => {
  const hidden = !$("palette").hidden;
  $("palette").hidden = hidden;
  $("toggle-palette").setAttribute("aria-pressed", String(!hidden));
});
const inspectorTabs = [
  ["tab-colors", "colors"],
  ["tab-shape", "shape"],
  ["tab-json", "json-panel"],
];
for (const [index, [tab, panel]] of inspectorTabs.entries()) {
  $(tab).tabIndex = index === 0 ? 0 : -1;
  $(tab).addEventListener("click", () => {
    for (const [t, p] of inspectorTabs) {
      $(t).setAttribute("aria-selected", String(t === tab));
      $(t).tabIndex = t === tab ? 0 : -1;
      $(p).hidden = p !== panel;
    }
  });
  $(tab).addEventListener("keydown", (event) => {
    let next;
    if (event.key === "ArrowRight") next = (index + 1) % inspectorTabs.length;
    if (event.key === "ArrowLeft")
      next = (index + inspectorTabs.length - 1) % inspectorTabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = inspectorTabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      const target = $(inspectorTabs[next][0]);
      target.click();
      target.focus();
    }
  });
}
$("validate-json").addEventListener("click", () => {
  try {
    const value = JSON.parse($("json-editor").value);
    validate(value, schema);
    theme = value;
    controls();
    render();
    message("Valid theme. Preview updated.");
  } catch (error) {
    message(error.message);
  }
});
$("export").addEventListener("click", () => {
  try {
    validate(theme, schema);
    const url = URL.createObjectURL(
      new Blob([JSON.stringify(theme, null, 2) + "\n"], {
        type: "application/json",
      }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download = `${theme.id}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    message("Theme exported. Make it yours, then share it.");
  } catch (error) {
    message(error.message);
  }
});
$("import").addEventListener("click", () => $("file").click());
$("file").addEventListener("change", async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  try {
    if (file.size > 32768) throw Error("Theme exceeds 32 KiB");
    const value = JSON.parse(await file.text());
    select(value);
    message(`Imported ${value.name}`);
  } catch (error) {
    message(error.message);
  } finally {
    e.target.value = "";
  }
});
$("apply").addEventListener("click", async () => {
  const button = $("apply");
  try {
    validate(theme, schema);
    button.disabled = true;
    const response = await fetch("api/apply", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Polar-Themes-Token": token,
      },
      body: JSON.stringify(theme),
    });
    const result = await response.json();
    if (!response.ok) throw Error(result.error);
    message(
      native
        ? `${theme.name} applied to Polar.`
        : `${theme.name} saved. Install the native adapter to see it in Polar.`,
    );
  } catch (error) {
    message(error.message);
  } finally {
    button.disabled = false;
  }
});
boot().catch((error) => message(error.message));
