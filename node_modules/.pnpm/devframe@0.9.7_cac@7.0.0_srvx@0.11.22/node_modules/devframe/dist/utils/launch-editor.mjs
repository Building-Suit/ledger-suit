import { i as __toESM, r as __require, t as __commonJSMin } from "../rolldown-runtime-B4iAMlE-.mjs";
//#region ../../node_modules/.pnpm/picocolors@1.1.1/node_modules/picocolors/picocolors.js
var require_picocolors = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	let p = process || {};
	let argv = p.argv || [];
	let env = p.env || {};
	let isColorSupported = !(!!env.NO_COLOR || argv.includes("--no-color")) && (!!env.FORCE_COLOR || argv.includes("--color") || p.platform === "win32" || (p.stdout || {}).isTTY && env.TERM !== "dumb" || !!env.CI);
	let formatter = (open, close, replace = open) => (input) => {
		let string = "" + input, index = string.indexOf(close, open.length);
		return ~index ? open + replaceClose(string, close, replace, index) + close : open + string + close;
	};
	let replaceClose = (string, close, replace, index) => {
		let result = "", cursor = 0;
		do {
			result += string.substring(cursor, index) + replace;
			cursor = index + close.length;
			index = string.indexOf(close, cursor);
		} while (~index);
		return result + string.substring(cursor);
	};
	let createColors = (enabled = isColorSupported) => {
		let f = enabled ? formatter : () => String;
		return {
			isColorSupported: enabled,
			reset: f("\x1B[0m", "\x1B[0m"),
			bold: f("\x1B[1m", "\x1B[22m", "\x1B[22m\x1B[1m"),
			dim: f("\x1B[2m", "\x1B[22m", "\x1B[22m\x1B[2m"),
			italic: f("\x1B[3m", "\x1B[23m"),
			underline: f("\x1B[4m", "\x1B[24m"),
			inverse: f("\x1B[7m", "\x1B[27m"),
			hidden: f("\x1B[8m", "\x1B[28m"),
			strikethrough: f("\x1B[9m", "\x1B[29m"),
			black: f("\x1B[30m", "\x1B[39m"),
			red: f("\x1B[31m", "\x1B[39m"),
			green: f("\x1B[32m", "\x1B[39m"),
			yellow: f("\x1B[33m", "\x1B[39m"),
			blue: f("\x1B[34m", "\x1B[39m"),
			magenta: f("\x1B[35m", "\x1B[39m"),
			cyan: f("\x1B[36m", "\x1B[39m"),
			white: f("\x1B[37m", "\x1B[39m"),
			gray: f("\x1B[90m", "\x1B[39m"),
			bgBlack: f("\x1B[40m", "\x1B[49m"),
			bgRed: f("\x1B[41m", "\x1B[49m"),
			bgGreen: f("\x1B[42m", "\x1B[49m"),
			bgYellow: f("\x1B[43m", "\x1B[49m"),
			bgBlue: f("\x1B[44m", "\x1B[49m"),
			bgMagenta: f("\x1B[45m", "\x1B[49m"),
			bgCyan: f("\x1B[46m", "\x1B[49m"),
			bgWhite: f("\x1B[47m", "\x1B[49m"),
			blackBright: f("\x1B[90m", "\x1B[39m"),
			redBright: f("\x1B[91m", "\x1B[39m"),
			greenBright: f("\x1B[92m", "\x1B[39m"),
			yellowBright: f("\x1B[93m", "\x1B[39m"),
			blueBright: f("\x1B[94m", "\x1B[39m"),
			magentaBright: f("\x1B[95m", "\x1B[39m"),
			cyanBright: f("\x1B[96m", "\x1B[39m"),
			whiteBright: f("\x1B[97m", "\x1B[39m"),
			bgBlackBright: f("\x1B[100m", "\x1B[49m"),
			bgRedBright: f("\x1B[101m", "\x1B[49m"),
			bgGreenBright: f("\x1B[102m", "\x1B[49m"),
			bgYellowBright: f("\x1B[103m", "\x1B[49m"),
			bgBlueBright: f("\x1B[104m", "\x1B[49m"),
			bgMagentaBright: f("\x1B[105m", "\x1B[49m"),
			bgCyanBright: f("\x1B[106m", "\x1B[49m"),
			bgWhiteBright: f("\x1B[107m", "\x1B[49m")
		};
	};
	module.exports = createColors();
	module.exports.createColors = createColors;
}));
//#endregion
//#region ../../node_modules/.pnpm/shell-quote@1.10.0/node_modules/shell-quote/quote.js
var require_quote = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	/** @import { ControlOperator } from './parse' */
	/** @type {ControlOperator['op'][]} */
	var OPS = [
		"||",
		"&&",
		";;",
		"|&",
		"<(",
		"<<<",
		">>",
		">&",
		"<&",
		"&",
		";",
		"(",
		")",
		"|",
		"<",
		">"
	];
	var LINE_TERMINATORS = /[\n\r\u2028\u2029]/;
	var GLOB_SHELL_SPECIAL = /[\s#!"$&'():;<=>@\\^`|]/g;
	/** @type {typeof import('./quote')} */
	module.exports = function quote(xs) {
		return xs.map(function(s) {
			if (s === "") return "''";
			if (s && typeof s === "object") {
				if ("op" in s && s.op === "glob") {
					if (typeof s.pattern !== "string") throw new TypeError("glob token requires a string `pattern`");
					if (LINE_TERMINATORS.test(s.pattern)) throw new TypeError("glob `pattern` must not contain line terminators");
					return s.pattern.replace(GLOB_SHELL_SPECIAL, "\\$&");
				}
				if ("op" in s && typeof s.op === "string") {
					if (OPS.indexOf(s.op) < 0) throw new TypeError("invalid `op` value: " + JSON.stringify(s.op));
					return s.op.replace(/[\s\S]/g, "\\$&");
				}
				if ("comment" in s && typeof s.comment === "string") {
					if (LINE_TERMINATORS.test(s.comment)) throw new TypeError("`comment` must not contain line terminators");
					return "#" + s.comment;
				}
				throw new TypeError("unrecognized object token shape");
			}
			if (/["\s\\]/.test(s) && !/'/.test(s)) return "'" + s.replace(/(['])/g, "\\$1") + "'";
			if (/["'\s]/.test(s)) return "\"" + s.replace(/(["\\$`!])/g, "\\$1") + "\"";
			return String(s).replace(/([A-Za-z]:)?([#!"$&'()*,:;<=>?@[\\\]^`{|}~])/g, "$1\\$2");
		}).join(" ");
	};
}));
//#endregion
//#region ../../node_modules/.pnpm/shell-quote@1.10.0/node_modules/shell-quote/parse.js
var require_parse = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	/**
	* @import {
	* 	ControlOperator,
	* 	Env,
	* 	GlobPattern,
	* 	ParseEntry,
	* } from './parse' */
	var CONTROL = "(?:" + [
		"\\|\\|",
		"\\&\\&",
		";;",
		"\\|\\&",
		"\\<\\(",
		"\\<\\<\\<",
		">>",
		">\\&",
		"<\\&",
		"[&;()|<>]"
	].join("|") + ")";
	var controlRE = new RegExp("^" + CONTROL + "$");
	var META = "|&;()<> \\t";
	var SINGLE_QUOTE = "'([^']*?)'";
	var DOUBLE_QUOTE = "\"((\\\\\"|[^\"])*?)\"";
	var hash = /^#$/;
	var SQ = "'";
	var DQ = "\"";
	var DS = "$";
	var TOKEN = "";
	var mult = 4294967296;
	for (var i = 0; i < 4; i++) TOKEN += (mult * Math.random()).toString(16);
	var startsWithToken = new RegExp("^" + TOKEN);
	/**
	* @param {string} s
	* @param {RegExp} r
	*/
	function matchAll(s, r) {
		var origIndex = r.lastIndex;
		var matches = [];
		var matchObj;
		while (matchObj = r.exec(s)) {
			matches[matches.length] = matchObj;
			if (r.lastIndex === matchObj.index) r.lastIndex += 1;
		}
		r.lastIndex = origIndex;
		return matches;
	}
	/**
	* @param {Env} env
	* @param {string} pre
	* @param {string} key
	*/
	function getVar(env, pre, key) {
		var r = typeof env === "function" ? env(key) : env[key];
		if (typeof r === "undefined" && key != "") r = "";
		else if (typeof r === "undefined") r = "$";
		if (typeof r === "object") return pre + TOKEN + JSON.stringify(r) + TOKEN;
		return pre + r;
	}
	/**
	* @param {string} string
	* @param {Env} [env]
	* @param {{ escape?: string, splitUnquoted?: boolean | string }} [opts]
	* @returns {ParseEntry[]}
	*/
	function parseInternal(string, env, opts) {
		if (!opts) opts = {};
		var BS = opts.escape || "\\";
		var ifs = opts.splitUnquoted === true ? " 	\n" : typeof opts.splitUnquoted === "string" ? opts.splitUnquoted : "";
		var BAREWORD = "(\\" + BS + "['\"" + META + "]|[^\\s'\"" + META + "])+";
		var matches = matchAll(string, new RegExp(["(" + CONTROL + ")", "(" + BAREWORD + "|" + DOUBLE_QUOTE + "|" + SINGLE_QUOTE + ")+"].join("|"), "g"));
		if (matches.length === 0) return [];
		if (!env) env = {};
		var commented = false;
		return matches.map(function(match) {
			var s = match[0];
			if (!s || commented) return;
			if (controlRE.test(s)) return { op: s };
			/** @type {string | boolean} */
			var quote = false;
			var esc = false;
			var out = "";
			/** @type {string[]} */
			var words = [];
			var sawQuote = false;
			/** @type {number | null} */
			var pendingNw = null;
			var isGlob = false;
			/** @type {number} */
			var i;
			function parseEnvVar() {
				i += 1;
				/** @type {number | RegExpMatchArray | null} */
				var varend;
				/** @type {string} */
				var varname;
				var char = s.charAt(i);
				if (char === "{") {
					i += 1;
					if (s.charAt(i) === "}") throw new Error("Bad substitution: " + s.slice(i - 2, i + 1));
					var depth = 1;
					varend = i;
					while (depth > 0 && varend < s.length) {
						if (s.charAt(varend) === "{" && s.charAt(varend - 1) === "$") depth += 1;
						else if (s.charAt(varend) === "}") depth -= 1;
						varend += 1;
					}
					if (depth !== 0) throw new Error("Bad substitution: " + s.slice(i));
					varend -= 1;
					varname = s.slice(i, varend);
					i = varend;
				} else if (/[*@#?$!_-]/.test(char)) {
					varname = char;
					i += 1;
				} else {
					var slicedFromI = s.slice(i);
					varend = slicedFromI.match(/[^\w\d_]/);
					if (!varend) {
						varname = slicedFromI;
						i = s.length;
					} else {
						varname = slicedFromI.slice(0, varend.index);
						i += varend.index - 1;
					}
				}
				return getVar(env, "", varname);
			}
			function flushRun() {
				if (pendingNw === null) return;
				if (pendingNw === 0) {
					if (out !== "") {
						words[words.length] = out;
						out = "";
					}
				} else {
					words[words.length] = out;
					out = "";
					for (var fe = 1; fe < pendingNw; fe += 1) words[words.length] = "";
				}
				pendingNw = null;
			}
			for (i = 0; i < s.length; i++) {
				var c = s.charAt(i);
				if (ifs && c !== DS) flushRun();
				isGlob = isGlob || !quote && (c === "*" || c === "?");
				if (esc) {
					out += c;
					esc = false;
				} else if (quote) {
					if (c === quote) quote = false;
					else if (quote == SQ) out += c;
					else if (c === BS) {
						i += 1;
						c = s.charAt(i);
						if (c === DQ || c === BS || c === DS) out += c;
						else out += BS + c;
					} else if (c === DS) out += parseEnvVar();
					else out += c;
				} else if (c === DQ || c === SQ) {
					quote = c;
					sawQuote = true;
				} else if (controlRE.test(c)) return { op: s };
				else if (hash.test(c)) {
					commented = true;
					var commentObj = { comment: string.slice(match.index + i + 1) };
					if (out.length) return [out, commentObj];
					return [commentObj];
				} else if (c === BS) esc = true;
				else if (c === DS) {
					var value = parseEnvVar();
					if (!ifs) out += value;
					else for (var vi = 0; vi < value.length; vi += 1) {
						var vc = value.charAt(vi);
						if (ifs.indexOf(vc) < 0) {
							flushRun();
							out += vc;
						} else if (pendingNw === null) pendingNw = vc === " " || vc === "	" || vc === "\n" ? 0 : 1;
						else if (vc !== " " && vc !== "	" && vc !== "\n") pendingNw += 1;
					}
				} else out += c;
			}
			if (isGlob) return {
				op: "glob",
				pattern: out
			};
			if (ifs) {
				if (pendingNw !== null && pendingNw > 0) {
					words[words.length] = out;
					out = "";
					for (var te = 1; te < pendingNw; te += 1) words[words.length] = "";
				}
				if (out !== "" || sawQuote && words.length === 0) words[words.length] = out;
				return words;
			}
			return out;
		}).reduce(function(prev, arg) {
			if (typeof arg === "undefined") return prev;
			/** @type {ParseEntry[]} */ [].concat(arg).forEach(function(entry) {
				prev[prev.length] = entry;
			});
			return prev;
		}, []);
	}
	/** @type {typeof import('./parse')} */
	module.exports = function parse(s, env, opts) {
		var mapped = parseInternal(s, env, opts);
		if (typeof env !== "function") return mapped;
		return mapped.reduce(function(acc, s) {
			if (typeof s === "object") {
				acc[acc.length] = s;
				return acc;
			}
			var xs = s.split(RegExp("(" + TOKEN + ".*?" + TOKEN + ")", "g"));
			if (xs.length === 1) {
				acc[acc.length] = xs[0];
				return acc;
			}
			xs.filter(Boolean).forEach(function(x) {
				acc[acc.length] = startsWithToken.test(x) ? JSON.parse(x.split(TOKEN)[1]) : x;
			});
			return acc;
		}, []);
	};
}));
//#endregion
//#region ../../node_modules/.pnpm/shell-quote@1.10.0/node_modules/shell-quote/index.js
var require_shell_quote = /* @__PURE__ */ __commonJSMin(((exports) => {
	exports.quote = require_quote();
	exports.parse = require_parse();
}));
//#endregion
//#region ../../node_modules/.pnpm/launch-editor@2.14.1/node_modules/launch-editor/editor-info/macos.js
var require_macos = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	module.exports = {
		"/Applications/Atom.app/Contents/MacOS/Atom": "atom",
		"/Applications/Atom Beta.app/Contents/MacOS/Atom Beta": "/Applications/Atom Beta.app/Contents/MacOS/Atom Beta",
		"/Applications/Brackets.app/Contents/MacOS/Brackets": "brackets",
		"/Applications/Sublime Text.app/Contents/MacOS/Sublime Text": "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl",
		"/Applications/Sublime Text.app/Contents/MacOS/sublime_text": "/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl",
		"/Applications/Sublime Text 2.app/Contents/MacOS/Sublime Text 2": "/Applications/Sublime Text 2.app/Contents/SharedSupport/bin/subl",
		"/Applications/Sublime Text Dev.app/Contents/MacOS/Sublime Text": "/Applications/Sublime Text Dev.app/Contents/SharedSupport/bin/subl",
		"/Applications/Visual Studio Code.app/Contents/MacOS/Code": "code",
		"/Applications/Visual Studio Code.app/Contents/MacOS/Electron": "code",
		"/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders": "code-insiders",
		"/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Electron": "code-insiders",
		"/Applications/VSCodium.app/Contents/MacOS/Electron": "codium",
		"/Applications/Cursor.app/Contents/MacOS/Cursor": "cursor",
		"/Applications/Trae.app/Contents/MacOS/Electron": "trae",
		"/Applications/Antigravity.app/Contents/MacOS/Electron": "antigravity",
		"/Applications/AppCode.app/Contents/MacOS/appcode": "/Applications/AppCode.app/Contents/MacOS/appcode",
		"/Applications/CLion.app/Contents/MacOS/clion": "/Applications/CLion.app/Contents/MacOS/clion",
		"/Applications/IntelliJ IDEA.app/Contents/MacOS/idea": "/Applications/IntelliJ IDEA.app/Contents/MacOS/idea",
		"/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea": "/Applications/IntelliJ IDEA Ultimate.app/Contents/MacOS/idea",
		"/Applications/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea": "/Applications/IntelliJ IDEA Community Edition.app/Contents/MacOS/idea",
		"/Applications/PhpStorm.app/Contents/MacOS/phpstorm": "/Applications/PhpStorm.app/Contents/MacOS/phpstorm",
		"/Applications/PyCharm.app/Contents/MacOS/pycharm": "/Applications/PyCharm.app/Contents/MacOS/pycharm",
		"/Applications/PyCharm CE.app/Contents/MacOS/pycharm": "/Applications/PyCharm CE.app/Contents/MacOS/pycharm",
		"/Applications/RubyMine.app/Contents/MacOS/rubymine": "/Applications/RubyMine.app/Contents/MacOS/rubymine",
		"/Applications/WebStorm.app/Contents/MacOS/webstorm": "/Applications/WebStorm.app/Contents/MacOS/webstorm",
		"/Applications/MacVim.app/Contents/MacOS/MacVim": "mvim",
		"/Applications/GoLand.app/Contents/MacOS/goland": "/Applications/GoLand.app/Contents/MacOS/goland",
		"/Applications/Rider.app/Contents/MacOS/rider": "/Applications/Rider.app/Contents/MacOS/rider",
		"/Applications/Zed.app/Contents/MacOS/zed": "zed"
	};
}));
//#endregion
//#region ../../node_modules/.pnpm/launch-editor@2.14.1/node_modules/launch-editor/editor-info/linux.js
var require_linux = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	module.exports = {
		atom: "atom",
		Brackets: "brackets",
		"code-insiders": "code-insiders",
		code: "code",
		vscodium: "vscodium",
		codium: "codium",
		cursor: "cursor",
		trae: "trae",
		antigravity: "antigravity",
		emacs: "emacs",
		gvim: "gvim",
		idea: "idea",
		"idea.sh": "idea",
		phpstorm: "phpstorm",
		"phpstorm.sh": "phpstorm",
		pycharm: "pycharm",
		"pycharm.sh": "pycharm",
		rubymine: "rubymine",
		"rubymine.sh": "rubymine",
		sublime_text: "subl",
		vim: "vim",
		webstorm: "webstorm",
		"webstorm.sh": "webstorm",
		goland: "goland",
		"goland.sh": "goland",
		rider: "rider",
		"rider.sh": "rider",
		zed: "zed"
	};
}));
//#endregion
//#region ../../node_modules/.pnpm/launch-editor@2.14.1/node_modules/launch-editor/editor-info/windows.js
var require_windows = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	module.exports = [
		"Brackets.exe",
		"Code.exe",
		"Code - Insiders.exe",
		"VSCodium.exe",
		"Cursor.exe",
		"atom.exe",
		"sublime_text.exe",
		"notepad++.exe",
		"clion.exe",
		"clion64.exe",
		"idea.exe",
		"idea64.exe",
		"phpstorm.exe",
		"phpstorm64.exe",
		"pycharm.exe",
		"pycharm64.exe",
		"rubymine.exe",
		"rubymine64.exe",
		"webstorm.exe",
		"webstorm64.exe",
		"goland.exe",
		"goland64.exe",
		"rider.exe",
		"rider64.exe",
		"Trae.exe",
		"zed.exe",
		"Antigravity.exe"
	];
}));
//#endregion
//#region ../../node_modules/.pnpm/launch-editor@2.14.1/node_modules/launch-editor/guess.js
var require_guess = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	const path$2 = __require("path");
	const shellQuote = require_shell_quote();
	const childProcess$1 = __require("child_process");
	const COMMON_EDITORS_MACOS = require_macos();
	const COMMON_EDITORS_LINUX = require_linux();
	const COMMON_EDITORS_WIN = require_windows();
	function getEditorFromMacProcesses(output) {
		const processNames = Object.keys(COMMON_EDITORS_MACOS);
		const processList = output.split("\n");
		for (let i = 0; i < processNames.length; i++) {
			const processName = processNames[i];
			if (processList.includes(processName)) return COMMON_EDITORS_MACOS[processName];
			const processNameWithoutApplications = processName.replace("/Applications", "");
			if (output.indexOf(processNameWithoutApplications) !== -1) {
				if (processName !== COMMON_EDITORS_MACOS[processName]) return COMMON_EDITORS_MACOS[processName];
				const runningProcess = processList.find((procName) => procName.endsWith(processNameWithoutApplications));
				if (runningProcess !== void 0) return runningProcess;
			}
		}
	}
	function getEditorFromWindowsProcesses(output) {
		const runningProcesses = output.split("\r\n");
		for (let i = 0; i < runningProcesses.length; i++) {
			const fullProcessPath = runningProcesses[i].trim();
			const shortProcessName = path$2.win32.basename(fullProcessPath);
			if (COMMON_EDITORS_WIN.indexOf(shortProcessName) !== -1) return fullProcessPath;
		}
	}
	function getEditorFromLinuxProcesses(output) {
		const processNames = Object.keys(COMMON_EDITORS_LINUX);
		for (let i = 0; i < processNames.length; i++) {
			const processName = processNames[i];
			if (output.indexOf(processName) !== -1) return COMMON_EDITORS_LINUX[processName];
		}
	}
	function guessEditor(specifiedEditor) {
		if (specifiedEditor) return shellQuote.parse(specifiedEditor);
		if (process.env.LAUNCH_EDITOR) return [process.env.LAUNCH_EDITOR];
		if (process.versions.webcontainer) return [process.env.EDITOR || "code"];
		try {
			if (process.platform === "darwin") {
				const editor = getEditorFromMacProcesses(childProcess$1.execSync("ps x -o comm=", { stdio: [
					"pipe",
					"pipe",
					"ignore"
				] }).toString());
				if (editor !== void 0) return [editor];
			} else if (process.platform === "win32") {
				const editor = getEditorFromWindowsProcesses(childProcess$1.execSync("powershell -NoProfile -Command \"[Console]::OutputEncoding=[Text.Encoding]::UTF8;Get-CimInstance -Query \\\"select executablepath from win32_process where executablepath is not null\\\" | % { $_.ExecutablePath }\"", { stdio: [
					"pipe",
					"pipe",
					"ignore"
				] }).toString());
				if (editor !== void 0) return [editor];
			} else if (process.platform === "linux") {
				const editor = getEditorFromLinuxProcesses(childProcess$1.execSync("ps x --no-heading -o comm --sort=comm", { stdio: [
					"pipe",
					"pipe",
					"ignore"
				] }).toString());
				if (editor !== void 0) return [editor];
			}
		} catch (ignoreError) {}
		if (process.env.VISUAL) return [process.env.VISUAL];
		else if (process.env.EDITOR) return [process.env.EDITOR];
		return [null];
	}
	module.exports = guessEditor;
	module.exports.getEditorFromMacProcesses = getEditorFromMacProcesses;
	module.exports.getEditorFromWindowsProcesses = getEditorFromWindowsProcesses;
	module.exports.getEditorFromLinuxProcesses = getEditorFromLinuxProcesses;
}));
//#endregion
//#region ../../node_modules/.pnpm/launch-editor@2.14.1/node_modules/launch-editor/get-args.js
var require_get_args = /* @__PURE__ */ __commonJSMin(((exports, module) => {
	const path$1 = __require("path");
	module.exports = function getArgumentsForPosition(editor, fileName, lineNumber, columnNumber = 1) {
		switch (path$1.basename(editor).replace(/\.(exe|cmd|bat)$/i, "")) {
			case "atom":
			case "Atom":
			case "Atom Beta":
			case "subl":
			case "sublime":
			case "sublime_text":
			case "wstorm":
			case "charm":
			case "zed": return [`${fileName}:${lineNumber}:${columnNumber}`];
			case "notepad++": return [
				"-n" + lineNumber,
				"-c" + columnNumber,
				fileName
			];
			case "vim":
			case "mvim": return [`+call cursor(${lineNumber}, ${columnNumber})`, fileName];
			case "joe":
			case "gvim": return [`+${lineNumber}`, fileName];
			case "emacs":
			case "emacsclient": return [`+${lineNumber}:${columnNumber}`, fileName];
			case "rmate":
			case "mate":
			case "mine": return [
				"--line",
				lineNumber,
				fileName
			];
			case "code":
			case "Code":
			case "code-insiders":
			case "Code - Insiders":
			case "codium":
			case "trae":
			case "antigravity":
			case "cursor":
			case "vscodium":
			case "VSCodium": return [
				"-r",
				"-g",
				`${fileName}:${lineNumber}:${columnNumber}`
			];
			case "appcode":
			case "clion":
			case "clion64":
			case "idea":
			case "idea64":
			case "phpstorm":
			case "phpstorm64":
			case "pycharm":
			case "pycharm64":
			case "rubymine":
			case "rubymine64":
			case "webstorm":
			case "webstorm64":
			case "goland":
			case "goland64":
			case "rider":
			case "rider64": return [
				"--line",
				lineNumber,
				"--column",
				columnNumber,
				fileName
			];
		}
		if (process.env.LAUNCH_EDITOR) return [
			fileName,
			lineNumber,
			columnNumber
		];
		return [fileName];
	};
}));
//#endregion
//#region src/utils/launch-editor.ts
var import_launch_editor = /* @__PURE__ */ __toESM((/* @__PURE__ */ __commonJSMin(((exports, module) => {
	/**
	* Copyright (c) 2015-present, Facebook, Inc.
	*
	* This source code is licensed under the MIT license found in the
	* LICENSE file at
	* https://github.com/facebookincubator/create-react-app/blob/master/LICENSE
	*
	* Modified by Yuxi Evan You
	*/
	const fs = __require("fs");
	const os = __require("os");
	const path = __require("path");
	const colors = require_picocolors();
	const childProcess = __require("child_process");
	const guessEditor = require_guess();
	const getArgumentsForPosition = require_get_args();
	function wrapErrorCallback(cb) {
		return (fileName, errorMessage) => {
			console.log();
			console.log(colors.red("Could not open " + path.basename(fileName) + " in the editor."));
			if (errorMessage) {
				if (errorMessage[errorMessage.length - 1] !== ".") errorMessage += ".";
				console.log(colors.red("The editor process exited with an error: " + errorMessage));
			}
			console.log();
			if (cb) cb(fileName, errorMessage);
		};
	}
	function isTerminalEditor(editor) {
		switch (editor) {
			case "vim":
			case "emacs":
			case "nano": return true;
		}
		return false;
	}
	const positionRE = /:(\d+)(:(\d+))?$/;
	function parseFile(file) {
		if (file.startsWith("file://")) file = __require("url").fileURLToPath(file);
		const fileName = file.replace(positionRE, "");
		const match = file.match(positionRE);
		return {
			fileName,
			lineNumber: match && match[1],
			columnNumber: match && match[3]
		};
	}
	let currentChildProcess = null;
	function launchEditor(file, specifiedEditor, onErrorCallback) {
		const parsed = parseFile(file);
		let { fileName } = parsed;
		const { lineNumber, columnNumber } = parsed;
		if (process.platform === "win32" && path.resolve(fileName).startsWith("\\\\")) return onErrorCallback(fileName, "UNC paths are not supported on Windows to avoid security issues. See https://github.com/vitejs/launch-editor/tree/main/packages/launch-editor#unc-paths-on-windows for details.");
		if (!fs.existsSync(fileName)) return;
		if (typeof specifiedEditor === "function") {
			onErrorCallback = specifiedEditor;
			specifiedEditor = void 0;
		}
		onErrorCallback = wrapErrorCallback(onErrorCallback);
		const [editor, ...args] = guessEditor(specifiedEditor);
		if (!editor) {
			onErrorCallback(fileName, null);
			return;
		}
		if (process.platform === "linux" && fileName.startsWith("/mnt/") && /Microsoft/i.test(os.release())) fileName = path.relative("", fileName);
		if (lineNumber) {
			const extraArgs = getArgumentsForPosition(editor, fileName, lineNumber, columnNumber);
			args.push.apply(args, extraArgs);
		} else args.push(fileName);
		if (currentChildProcess && isTerminalEditor(editor)) currentChildProcess.kill("SIGKILL");
		if (process.platform === "win32") {
			function escapeCmdArgs(cmdArgs) {
				return cmdArgs.replace(/([&|<>,;=^])/g, "^$1");
			}
			function doubleQuoteIfNeeded(str) {
				if (str.includes("^")) return `^"${str}^"`;
				else if (str.includes(" ")) return `"${str}"`;
				return str;
			}
			const launchCommand = [editor, ...args.map(escapeCmdArgs)].map(doubleQuoteIfNeeded).join(" ");
			currentChildProcess = childProcess.exec(launchCommand, {
				stdio: "inherit",
				shell: true
			});
		} else currentChildProcess = childProcess.spawn(editor, args, { stdio: "inherit" });
		currentChildProcess.on("exit", function(errorCode) {
			currentChildProcess = null;
			if (errorCode) onErrorCallback(fileName, "(code " + errorCode + ")");
		});
		currentChildProcess.on("error", function(error) {
			let { code, message } = error;
			if ("ENOENT" === code) message = `${message} ('${editor}' command does not exist in 'PATH')`;
			onErrorCallback(fileName, message);
		});
	}
	module.exports = launchEditor;
})))(), 1);
/**
* Open a file in the user's editor.
*
* `target` may be a plain path, `file:line`, or `file:line:column`.
*
* If `editor` is provided, it is used as the editor command (e.g. `'code'`,
* `'subl'`) or absolute binary path. Otherwise the editor is auto-detected
* via the `LAUNCH_EDITOR` env var with a fallback to common defaults.
*/
function launchEditor(target, editor) {
	(0, import_launch_editor.default)(target, editor);
}
//#endregion
export { launchEditor };
