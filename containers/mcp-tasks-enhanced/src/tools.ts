import _ from 'lodash'
import type { ZodSchema } from 'zod'
import { z } from 'zod'
import env from './env.js'
import metadata from './metadata.js'
import pkg from './pkg.js'
import schemas from './schemas.js'
import sources from './sources.js'
import storage from './storage.js'
import type { Tool } from './types.js'
import util from './util.js'

const tools = {
  setup: defineTool('setup', {
    schema: z.object({
      workspace: z.string().optional().describe('Workspace/project directory path (provided by the IDE or use $PWD)'),
      source_path: schemas.sourcePath,
    }),
    fromArgs: ([sourcePath, workspace]) => ({ source_path: sourcePath, workspace: workspace || undefined }),
    description: util.trimLines(`
      Initializes an source file from a path
      - Always call once per conversation when asked to use these tools
      - Ask the user to clarify the file path if not given, before calling this tool
      - Creates the file if it does not exist
      - Returns the source ID for further use
      ${env.INSTRUCTIONS ? `- ${env.INSTRUCTIONS}` : ''}
    `),
    handler: (args) => {
      storage.getParser(args.source_path)
      // Register the source and get ID
      const source = sources.register(args.source_path, args.workspace)
      return getSummary(source.id)
    },
  }),

  search: defineTool('search', {
    schema: z.object({
      source_id: schemas.sourceId,
      statuses: z.array(schemas.status).optional().describe('Specific statuses to get. Gets all if omitted'),
      terms: z.array(z.string()).optional().describe('Search terms to filter tasks by text or status (case-insensitive, OR logic, no regex or wildcards)'),
      ids: schemas.ids.optional().describe('Optional list of task IDs to search for'),
      limit: z.number().int().min(1).optional().describe('Maximum number of results (only for really large task lists)'),
    }),
    fromArgs: ([statuses = '', terms = '']) => ({ statuses: split(statuses), terms: split(terms) }),
    description: 'Search tasks from specific statuses with optional text & ID filtering',
    isReadOnly: true,
    handler: (args) => {
      const meta = metadata.load(args.source_id)
      const groups = args.statuses?.length ? args.statuses : meta.statuses
      let results = groups.flatMap(status => meta.groups[status] || [])

      if (args.ids) {
        results = results.filter(task => args.ids!.includes(task.id))
      }

      if (args.terms?.length) {
        results = results.filter(task => args.terms!.some(term =>
          util.fuzzySearch(`${task.text} ${task.status}`, term),
        ))
      }
      if (args.limit) {
        results = results.slice(0, args.limit)
      }
      return results
    },
  }),

  add: defineTool('add', {
    schema: z.object({
      source_id: schemas.sourceId,
      texts: z.array(z.string().min(1)).describe('Each text becomes a task'),
      description: z.string().optional().describe('Detailed description (blockquotes/notes). Only applied if adding a SINGLE task.').or(z.array(z.string())),
      status: schemas.status,
      index: schemas.index,
    }),
    fromArgs: ([text, status = env.STATUS_TODO, index, description]) => ({ texts: [text], status, index: index ? Number(index) : undefined, description }),
    description: 'Add new tasks with a specific status. It\'s faster and cheaper if you use this in batch. User can add atomically while AI works using the CLI add tool',
    handler: (args, context) => {
      const meta = metadata.load(args.source_id)

      const items: (string | import('./types.js').TaskEntry)[] = args.texts.map(text => {
        // If single task and description provided
        if (args.texts.length === 1 && args.description) {
          const descLines = Array.isArray(args.description) ? args.description : args.description.split('\n')
          return { text, description: descLines }
        }
        return text
      })

      return performAdd(meta, items, args.status, args.index, context)
    },
  }),

  update: defineTool('update', {
    schema: z.object({
      source_id: schemas.sourceId,
      ids: schemas.ids,
      status: z.union([schemas.status, z.literal(env.STATUS_DELETED)]).describe(util.trimLines(`
        ${schemas.status.description}
        - "${env.STATUS_DELETED}" when they want these removed
        ${env.AUTO_WIP ? `- Updating tasks to ${env.STATUS_WIP} moves others to ${env.STATUS_TODO}, finishing a ${env.STATUS_WIP} task moves the first ${env.STATUS_DONE} to ${env.STATUS_WIP}` : ''}
      `)),
      index: schemas.index,
    }),
    fromArgs: ([taskIds, status]) => ({ ids: split(taskIds) || [], status }),
    description: 'Update tasks in bulk by ID to a different status. Returns complete summary no need to call tasks_summary afterwards. Prevents AI accidentally rename or deleting tasks during mass updates, not even possible',
    handler: (args, context = {}) => {
      const meta = metadata.load(args.source_id)
      const items = args.ids.map((id) => {
        const task = meta.tasksByIdOrText[id]
        if (task) {
          // Preserve description!
          if (task.description && task.description.length > 0) {
            return { text: task.text, description: task.description }
          }
          return task.text
        }
        if (util.isId(id)) {
          throw new Error(`Task ID ${id} not found`)
        }
        // Assume the AI passed a text for a new task by mistake
        return id
      })

      return performAdd(meta, items, args.status, args.index, { ...context, update: true })
    },
  }),

  summary: defineTool('summary', {
    schema: z.object({
      source_id: schemas.sourceId,
    }),
    fromArgs: () => ({}),
    description: 'Get per-status task counts and the WIP task(s). Redundant right after tasks_add/tasks_update',
    isReadOnly: true,
    handler: (args) => {
      return getSummary(args.source_id)
    },
  }),

  debug: defineTool('debug', {
    schema: z.object({}),
    fromArgs: () => ({}),
    description: util.trimLines(`
      Get debug information about the MCP server and context
      - ${pkg.name} is at version ${pkg.version}
    `),
    isReadOnly: true,
    isEnabled: env.DEBUG,
    handler: (args, context) => {
      return {
        ...args, processEnv: process.env, argv: process.argv,
        env, context, version: pkg.version, CWD: util.CWD, ROOT: util.REPO,
      }
    },
  }),
} as const satisfies Record<string, Tool>

function getSummary(sourceId?: string, extra?: object) {
  const meta = metadata.load(sourceId)
  const counts = _.mapValues(meta.groups, tasks => tasks.length)
  const total = Object.values(counts).reduce((sum, count) => sum + count, 0)
  const wip = _.camelCase(env.STATUS_WIP)
  return JSON.stringify({
    source: _.omit(meta.source, ['workspace']),
    ...counts, total, ...extra,
    instructions: env.INSTRUCTIONS || undefined,
    reminders: env.STATUS_REMINDERS ? meta.groups[env.STATUS_REMINDERS] : undefined,
    [wip]: meta.groups[env.STATUS_WIP],
  })
}

function defineTool<S extends ZodSchema>(name: string, tool: {
  schema: S
  description: string
  isResource?: boolean
  isReadOnly?: boolean
  isEnabled?: boolean
  handler: (args: z.infer<S>, context?: any) => any
  fromArgs: (args: string[]) => z.infer<S>
}) {
  const toolName = env.PREFIX_TOOLS ? `tasks_${name}` : name
  return {
    ...tool,
    name: toolName,
    isResource: tool.isResource ?? false,
    isReadOnly: tool.isReadOnly ?? false,
    isEnabled: tool.isEnabled ?? true,
  }
}

function split(str: string): string[] | undefined {
  return str.length > 0 ? str.split(/\s*,\s*/).filter(Boolean) : undefined
}

export default tools

function performAdd(meta: import('./types.js').Metadata, items: (string | import('./types.js').TaskEntry)[], status: string, index?: number, context?: any) {
  const { source, state } = meta

  // Extract texts for comparison/logging
  const texts = items.map(i => typeof i === 'string' ? i : i.text)

  // Remove existing tasks with same text from all groups (duplicate handling)
  for (const groupName of meta.statuses) {
    if (state.groups[groupName]) {
      state.groups[groupName] = state.groups[groupName].filter(item => {
        const t = typeof item === 'string' ? item : item.text
        return !texts.includes(t)
      })
    }
  }

  let group = state.groups[status]
  // Special handling for Deleted and other unknown statuses
  if (!group) {
    storage.save(source.path, state)
    return getSummary(source.id)
  }

  const wip = state.groups[env.STATUS_WIP]
  const todos = state.groups[env.STATUS_TODO]

  if (env.AUTO_WIP && status === env.STATUS_WIP) {
    // Move all WIP but the first to ToDo
    todos.unshift(...wip)
    wip.length = 0
  }

  // Add new tasks at the specified index
  const idx = util.clamp(index ?? group.length, 0, group.length)
  group.splice(idx, 0, ...items)

  const isUpdate = !!context?.update

  // Helper to safely get text from first item of a group
  const getFirstText = (grp: (string | import('./types.js').TaskEntry)[]) => {
    if (!grp || !grp.length) return null
    return typeof grp[0] === 'string' ? grp[0] : grp[0].text
  }

  if (env.AUTO_WIP && !wip.length) {
    const firstTodoText = getFirstText(todos)
    if (firstTodoText && (firstTodoText !== texts[0] || isUpdate)) {
      // Move first ToDo to WIP (but not for updates)
      // We must shift the actual item (preserving object/description)
      const itemToMove = todos.shift()!
      wip.push(itemToMove)
    }
  }

  storage.save(source.path, state)
  // Re-load metadata after state changes
  meta = metadata.load(source.id)
  const affected = _.compact(texts.map(t => meta.tasksByIdOrText[t]))
  return getSummary(source.id, { [isUpdate ? 'updated' : 'added']: affected })
}
