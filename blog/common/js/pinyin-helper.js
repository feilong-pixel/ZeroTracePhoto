import { html, addDict } from "pinyin-pro";

export function usePinyinDict(dict) {
	if (dict) {
		addDict(dict);
	}
}

export function annotateElement(target, options = {}) {
	const element = typeof target === "string" ? document.querySelector(target) : target;

	if (!element) {
		return;
	}

	const sourceText = options.text ?? element.textContent;
	element.innerHTML = html(sourceText);
}

export function annotateElements(targets, options = {}) {
	targets.forEach((target) => annotateElement(target, options));
}

export function annotateIdRange(prefix, start, end, options = {}) {
	const targets = [];

	for (let i = start; i <= end; i += 1) {
		targets.push(`#${prefix}${String(i).padStart(2, "0")}`);
	}

	annotateElements(targets, options);
}

export function onReady(callback) {
	if (document.readyState === "loading") {
		document.addEventListener("DOMContentLoaded", callback, { once: true });
		return;
	}

	callback();
}
