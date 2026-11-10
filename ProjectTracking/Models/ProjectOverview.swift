import Foundation

/// Built once per data revision rather than filtering the whole vault in each View.
nonisolated struct ProjectOverview {
    let active: [Project]
    let archived: [Project]
    let byID: [UUID: Project]
    let openTasks: [TaskContext]
    let totalTasks: Int
    let doneTasks: Int

    init(projects: [Project]) {
        var active: [Project] = [], archived: [Project] = []
        var byID: [UUID: Project] = [:]
        var open: [TaskContext] = []
        var total = 0, done = 0
        for project in projects {
            byID[project.id] = project
            if project.isCompleted { archived.append(project); continue }
            active.append(project)
            total += project.tasks.count
            for task in project.tasks {
                if task.isDone { done += 1 }
                else { open.append(TaskContext(project: project, task: task)) }
            }
        }
        self.active = active
        self.archived = archived
        self.byID = byID
        self.openTasks = open
        self.totalTasks = total
        self.doneTasks = done
    }
}
