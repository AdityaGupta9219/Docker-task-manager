const API_URL = '/api';

class TaskManager {
    constructor() {
        this.taskForm = document.getElementById('taskForm');
        this.taskInput = document.getElementById('taskInput');
        this.taskList = document.getElementById('taskList');
        
        this.init();
    }
    
    init() {
        this.taskForm.addEventListener('submit', this.addTask.bind(this));
        this.loadTasks();
    }
    
    async loadTasks() {
        try {
            const response = await fetch(`${API_URL}/tasks`);
            const tasks = await response.json();
            this.renderTasks(tasks);
        } catch (error) {
            console.error('Error loading tasks:', error);
        }
    }
    
    async addTask(e) {
        e.preventDefault();
        const title = this.taskInput.value.trim();
        
        if (!title) return;
        
        try {
            const response = await fetch(`${API_URL}/tasks`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ title })
            });
            
            if (response.ok) {
                this.taskInput.value = '';
                this.loadTasks();
            }
        } catch (error) {
            console.error('Error adding task:', error);
        }
    }
    
    async toggleTask(id, completed) {
        try {
            await fetch(`${API_URL}/tasks/${id}`, {
                method: 'PATCH',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ completed: !completed })
            });
            this.loadTasks();
        } catch (error) {
            console.error('Error updating task:', error);
        }
    }
    
    async deleteTask(id) {
        try {
            await fetch(`${API_URL}/tasks/${id}`, {
                method: 'DELETE'
            });
            this.loadTasks();
        } catch (error) {
            console.error('Error deleting task:', error);
        }
    }
    
    renderTasks(tasks) {
        this.taskList.innerHTML = tasks.map(task => `
            <li class="task-item ${task.completed ? 'completed' : ''}">
                <input type="checkbox" ${task.completed ? 'checked' : ''} 
                       onchange="taskManager.toggleTask('${task._id}', ${task.completed})">
                <span class="task-text">${task.title}</span>
                <button class="delete-btn" onclick="taskManager.deleteTask('${task._id}')">
                    Delete
                </button>
            </li>
        `).join('');
    }
}

const taskManager = new TaskManager();