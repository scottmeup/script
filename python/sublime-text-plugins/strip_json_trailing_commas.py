# scans text without treating string/comment content as structure
# Sublime syntax limits scope rather than filename extension

import sublime
import sublime_plugin

SETTING_KEY = "strip_json_trailing_commas_on_save"
JSON_SELECTOR = "source.json"


def find_trailing_commas(text):
    commas = []
    length = len(text)
    index = 0
    state = "code"

    while index < length:
        char = text[index]
        following = text[index + 1] if index + 1 < length else ""

        if state == "string":
            if char == "\\":
                index += 2
                continue
            if char == '"':
                state = "code"
            index += 1
            continue

        if state == "line_comment":
            if char in "\r\n":
                state = "code"
            index += 1
            continue

        if state == "block_comment":
            if char == "*" and following == "/":
                state = "code"
                index += 2
            else:
                index += 1
            continue

        if char == '"':
            state = "string"
            index += 1
            continue
        if char == "/" and following == "/":
            state = "line_comment"
            index += 2
            continue
        if char == "/" and following == "*":
            state = "block_comment"
            index += 2
            continue

        if char == ",":
            lookahead = index + 1
            while lookahead < length:
                candidate = text[lookahead]
                next_candidate = text[lookahead + 1] if lookahead + 1 < length else ""
                if candidate.isspace():
                    lookahead += 1
                    continue
                if candidate == "/" and next_candidate == "/":
                    newline = text.find("\n", lookahead + 2)
                    lookahead = length if newline == -1 else newline + 1
                    continue
                if candidate == "/" and next_candidate == "*":
                    comment_end = text.find("*/", lookahead + 2)
                    if comment_end == -1:
                        lookahead = length
                    else:
                        lookahead = comment_end + 2
                    continue
                break
            if lookahead < length and text[lookahead] in "}]":
                commas.append(index)

        index += 1

    return commas


def is_json_family_view(view):
    if view.size() == 0:
        return view.match_selector(0, JSON_SELECTOR)
    return view.match_selector(0, JSON_SELECTOR)


class StripJsonTrailingCommasCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        text = self.view.substr(sublime.Region(0, self.view.size()))
        commas = find_trailing_commas(text)
        for point in reversed(commas):
            self.view.erase(edit, sublime.Region(point, point + 1))
        if commas:
            sublime.status_message("Removed {} trailing JSON comma(s)".format(len(commas)))

    def is_enabled(self):
        return is_json_family_view(self.view)


class StripJsonTrailingCommasOnSaveListener(sublime_plugin.EventListener):
    def on_pre_save(self, view):
        if not view.settings().get(SETTING_KEY, True):
            return
        if is_json_family_view(view):
            view.run_command("strip_json_trailing_commas")
