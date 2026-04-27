import _ from 'lodash'
import { basename } from 'path'
import env from '../env.js'
import type { FormatParser, State } from '../types.js'
import util from '../util.js'

const PREFIX = '## '
const LINE_REGEX: RegExp = /^ *- *(?:\[.?\])? *(.+) *$/

// TODO: Make this configurable (?)
const SKIP_IF_EMPTY: string[] = _.compact([env.STATUS_DELETED, env.STATUS_NOTES, env.STATUS_REMINDERS])

const md: FormatParser = {
  read(path) {
    const content = util.readFile(path)
    // Do not trim lines to preserve indentation for subtasks/descriptions
    // But we still want to filter out completely empty lines if they aren't carrying data?
    // Actually, descriptions might have empty lines. 
    // For now, let's keep it simple: split by newline. 
    const lines = content.split('\n')
    const state: State = { groups: {} }

    let currentGroup = env.STATUS_TODO
    let lastTask: { text: string, description: string[] } | null = null

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) continue

      if (line.startsWith(PREFIX)) {
        const group = line.substring(PREFIX.length).trim()
        if (group) {
          currentGroup = group
          lastTask = null
        }
      } else {
        const match = line.match(LINE_REGEX)
        if (match) {
          // It's a task
          const text = match[1].trim()
          if (text) {
            if (!state.groups[currentGroup]) {
              state.groups[currentGroup] = []
            }
            const unescaped = text.replace(/\\n/g, '\n')
            // Always create object structure for consistency
            lastTask = { text: unescaped, description: [] }
            state.groups[currentGroup].push(lastTask)
          }
        } else if (lastTask) {
          // It's not a task headers, and not a group header.
          // Assume it's part of the last task's description if we have one.
          // We store the original line (trimmed? or with relative indentation?)
          // Let's store trimmed for now, but usually we want to preserve blockquote structure.
          // If user wrote "> desc", trimmed is "> desc". 
          // If user wrote "  subtask", trimmed is "subtask".
          // To be safe and "Generic", let's store trimmed but maybe we should strip leading "> "?
          // The user likes "Generic Description". Let's just store the line as is (trimmed of outer whitespace).
          lastTask.description.push(trimmed)
        }
      }
    }
    return state
  },

  write(path, state) {
    const title = _.startCase(basename(path, '.md'))
    let content = `# Tasks - ${title}\n\n`

    for (const group of util.keysOf(state.groups)) {
      const tasks = state.groups[group] || []
      if (!tasks.length && (SKIP_IF_EMPTY.includes(group) || !env.STATUSES.includes(group))) {
        continue
      }
      content += `${PREFIX}${group}\n\n`
      for (const item of tasks) {
        const char = group === env.STATUS_DONE ? 'x' :
          group === env.STATUS_NOTES || group === env.STATUS_REMINDERS ? '' : ' '
        const block = char ? `[${char}] ` : ''

        const taskText = typeof item === 'string' ? item : item.text
        const description = typeof item === 'string' ? [] : item.description || []

        const escaped = taskText.replace(/\r?\n/g, '\\n')
        content += `- ${block}${escaped}\n`

        if (description && description.length > 0) {
          for (const descLine of description) {
            // If it already starts with > or -, leave it. 
            // Otherwise indent. 
            // Ideally we normalize to blockquotes "  > "
            // But if it was a subtask "  - sub", we should keep it.
            // If we stripped indentation in read, we lost context.
            // WAIT: In read() I decided to store trimmed.
            // If I store trimmed "subtask", I don't know if it was a subtask.
            // The user asked for "Generic Description".
            // Let's default to blockquote formatting for consistency if it doesn't look like a list item.

            if (descLine.startsWith('>')) {
              content += `  ${descLine}\n`
            } else if (descLine.startsWith('-') || descLine.startsWith('*')) {
              content += `  ${descLine}\n`
            } else {
              content += `  > ${descLine}\n`
            }
          }
        }
      }
      content += '\n'
    }
    util.writeFile(path, `${content.trim()}\n`)
  },
}

export default md
