// 学习系统主要功能
class StudySystem {
    constructor() {
        this.currentQuestion = null;
        this.isEditMode = true;
        this.questions = this.loadQuestions();
        this.history = this.loadHistory();
        this.tags = this.loadTags();
        this.annotations = {};
        this.autoSaveTimer = null;
        this.cloudSyncEnabled = false;
        
        // 等待认证管理器初始化完成
        setTimeout(() => {
            this.cloudSyncEnabled = window.authManager && window.authManager.isLoggedIn();
            this.init();
        }, 100);
    }
    
    // 检查用户是否有权限编辑题目
    canEditQuestion(question) {
        if (!window.authManager || !window.authManager.isLoggedIn()) {
            return false;
        }
        
        // 管理员可以编辑所有题目
        if (window.authManager.isAdmin()) {
            return true;
        }
        
        // 普通用户只能编辑自己创建的题目
        return question.createdBy === window.authManager.user.id;
    }
    
    // 检查用户是否有权限删除题目
    canDeleteQuestion(question) {
        return this.canEditQuestion(question);
    }
    
    // 检查用户是否有权限查看题目
    canViewQuestion(question) {
        if (!window.authManager || !window.authManager.isLoggedIn()) {
            return false;
        }
        
        // 管理员可以查看所有题目
        if (window.authManager.isAdmin()) {
            return true;
        }
        
        // 普通用户可以查看自己的题目和公开题目
        return question.createdBy === window.authManager.user.id || question.isPublic;
    }
    
    init() {
        this.bindEvents();
        this.renderQuestionsList();
        this.renderHistory();
        this.renderTags();
        this.setupAutoSave();
        this.initCategoryNavigation();
    }
    
    // 事件绑定
    bindEvents() {
        // 页面导航
        document.getElementById('backToListBtn').addEventListener('click', () => {
            this.showQuestionsList();
        });
        
        // 模式切换
        document.getElementById('editModeBtn').addEventListener('click', () => {
            this.setEditMode(true);
        });
        
        document.getElementById('readModeBtn').addEventListener('click', () => {
            this.setEditMode(false);
        });
        
        // 新建题目
        document.getElementById('newQuestionBtn').addEventListener('click', () => {
            this.createNewQuestion();
        });
        
        // 导入文档
        document.getElementById('importDocBtn').addEventListener('click', () => {
            document.getElementById('fileInput').click();
        });
        
        document.getElementById('fileInput').addEventListener('change', (e) => {
            this.importDocument(e.target.files[0]);
        });
        
        // 高亮工具
        document.querySelectorAll('.highlight-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                this.applyHighlight(btn.dataset.color);
            });
        });
        
        document.querySelector('.clear-highlight-btn').addEventListener('click', () => {
            this.clearHighlight();
        });
        
        // 显示思路按钮
        document.getElementById('showThinkingBtn').addEventListener('click', () => {
            this.toggleThinking();
        });
        
        // 搜索和过滤
        document.getElementById('searchInput').addEventListener('input', () => {
            this.filterQuestions();
        });
        
        document.getElementById('categoryFilter').addEventListener('change', () => {
            this.updateSubcategoryFilter();
            this.filterQuestions();
        });
        
        document.getElementById('subcategoryFilter').addEventListener('change', () => {
            this.filterQuestions();
        });
        
        // 标签管理
        document.getElementById('addTagBtn').addEventListener('click', () => {
            this.addTag();
        });
        
        document.getElementById('newTag').addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.addTag();
            }
        });
        
        // 删除题目
        document.getElementById('deleteQuestionBtn').addEventListener('click', () => {
            this.deleteCurrentQuestion();
        });
        
        // 批注模态框
        document.getElementById('saveAnnotationBtn').addEventListener('click', () => {
            this.saveAnnotation();
        });
        
        document.getElementById('cancelAnnotationBtn').addEventListener('click', () => {
            this.closeAnnotationModal();
        });
        
        document.querySelector('.close-btn').addEventListener('click', () => {
            this.closeAnnotationModal();
        });
        
        // 点击模态框外部关闭
        document.getElementById('annotationModal').addEventListener('click', (e) => {
            if (e.target.id === 'annotationModal') {
                this.closeAnnotationModal();
            }
        });
    }
    
    // 分类导航初始化
    initCategoryNavigation() {
        document.querySelectorAll('.category-title').forEach(title => {
            title.addEventListener('click', () => {
                const subcategoryList = title.nextElementSibling;
                const isActive = title.classList.contains('active');
                
                // 关闭所有其他分类
                document.querySelectorAll('.category-title').forEach(t => {
                    t.classList.remove('active');
                    t.nextElementSibling.classList.remove('active');
                });
                
                if (!isActive) {
                    title.classList.add('active');
                    subcategoryList.classList.add('active');
                }
            });
        });
        
        // 子分类点击
        document.querySelectorAll('.subcategory-list li').forEach(item => {
            item.addEventListener('click', () => {
                // 移除其他活动状态
                document.querySelectorAll('.subcategory-list li').forEach(li => {
                    li.classList.remove('active');
                });
                
                item.classList.add('active');
                
                // 设置过滤器
                const category = item.closest('.category-group').querySelector('.category-title').dataset.category;
                const subcategory = item.dataset.subcategory;
                
                document.getElementById('categoryFilter').value = category;
                this.updateSubcategoryFilter();
                document.getElementById('subcategoryFilter').value = subcategory;
                this.filterQuestions();
            });
        });
    }
    
    // 创建新题目
    createNewQuestion() {
        const question = {
            id: Date.now().toString(),
            title: '新题目',
            category: '申论',
            subcategory: '概括归纳',
            content: '',
            summary: '',
            example: '',
            thinking: '',
            notes: '',
            tags: [],
            createdBy: window.authManager && window.authManager.user ? window.authManager.user.id : null,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
        };
        
        this.questions.push(question);
        this.saveQuestions();
        this.showQuestionDetail(question);
    }
    
    // 导入文档
    async importDocument(file) {
        if (!file) return;
        
        const reader = new FileReader();
        reader.onload = (e) => {
            const content = e.target.result;
            const question = {
                id: Date.now().toString(),
                title: file.name.replace(/\.[^/.]+$/, ""),
                category: '申论',
                subcategory: '概括归纳',
                content: content,
                summary: '',
                example: '',
                thinking: '',
                notes: '',
                tags: [],
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString()
            };
            
            this.questions.push(question);
            this.saveQuestions();
            this.renderQuestionsList();
            this.showQuestionDetail(question);
        };
        
        reader.readAsText(file);
    }
    
    // 显示题目列表
    showQuestionsList() {
        document.getElementById('questionListPage').classList.add('active');
        document.getElementById('questionDetailPage').classList.remove('active');
        this.renderQuestionsList();
    }
    
    // 显示题目详情
    showQuestionDetail(question) {
        this.currentQuestion = question;
        this.addToHistory(question);
        
        document.getElementById('questionListPage').classList.remove('active');
        document.getElementById('questionDetailPage').classList.add('active');
        
        // 填充题目信息
        document.getElementById('questionTitle').textContent = question.title;
        document.getElementById('questionCategory').textContent = question.category;
        document.getElementById('questionSubcategory').textContent = question.subcategory;
        
        // 填充内容
        document.getElementById('questionContent').innerHTML = question.content || '';
        document.getElementById('summaryContent').innerHTML = question.summary || '';
        document.getElementById('exampleContent').innerHTML = question.example || '';
        document.getElementById('thinkingContent').innerHTML = question.thinking || '';
        document.getElementById('notesContent').innerHTML = question.notes || '';
        
        // 加载批注
        this.loadAnnotations(question.id);
        
        // 根据权限设置编辑模式和按钮显示
        const canEdit = this.canEditQuestion(question);
        const canDelete = this.canDeleteQuestion(question);
        
        // 控制编辑模式按钮显示
        document.getElementById('editModeBtn').style.display = canEdit ? 'inline-block' : 'none';
        document.getElementById('readModeBtn').style.display = canEdit ? 'inline-block' : 'none';
        
        // 控制删除按钮显示
        const deleteBtn = document.getElementById('deleteQuestionBtn');
        if (deleteBtn) {
            deleteBtn.style.display = canDelete ? 'inline-block' : 'none';
        }
        
        // 设置编辑模式（如果没有编辑权限，强制为只读模式）
        this.setEditMode(canEdit && this.isEditMode);
        
        // 绑定高亮点击事件
        this.bindHighlightEvents();
        
        // 重置思路显示状态
        document.getElementById('thinkingContent').classList.add('hidden');
        document.getElementById('showThinkingBtn').textContent = '显示思路';
    }
    
    // 设置编辑模式
    setEditMode(isEdit) {
        this.isEditMode = isEdit;
        
        // 更新按钮状态
        document.getElementById('editModeBtn').classList.toggle('active', isEdit);
        document.getElementById('readModeBtn').classList.toggle('active', !isEdit);
        
        // 更新内容区域
        const editableElements = document.querySelectorAll('.editable-content');
        editableElements.forEach(el => {
            el.contentEditable = isEdit;
        });
        
        // 显示/隐藏高亮工具
        document.getElementById('highlightTools').style.display = isEdit ? 'flex' : 'none';
        
        // 在阅读模式下自动显示所有批注
        if (!isEdit) {
            this.showAllAnnotations();
        } else {
            // 编辑模式下清空批注面板
            document.getElementById('annotationsContainer').innerHTML = 
                '<div class="no-annotations">点击高亮文字查看批注</div>';
        }
    }
    
    // 应用高亮
    applyHighlight(color) {
        if (!this.isEditMode) return;
        
        const selection = window.getSelection();
        if (selection.rangeCount === 0 || selection.toString().trim() === '') return;
        
        const range = selection.getRangeAt(0);
        const selectedText = selection.toString();
        
        // 创建高亮元素
        const highlightSpan = document.createElement('span');
        highlightSpan.className = `highlight ${color}`;
        highlightSpan.dataset.id = Date.now().toString();
        highlightSpan.dataset.text = selectedText;
        
        try {
            range.surroundContents(highlightSpan);
            selection.removeAllRanges();
            
            // 绑定点击事件
            highlightSpan.addEventListener('click', (e) => {
                e.stopPropagation();
                this.showAnnotationModal(highlightSpan);
            });
            
            this.autoSave();
        } catch (e) {
            console.warn('无法应用高亮到选中的内容');
        }
    }
    
    // 清除高亮
    clearHighlight() {
        if (!this.isEditMode) return;
        
        const selection = window.getSelection();
        if (selection.rangeCount === 0) return;
        
        const range = selection.getRangeAt(0);
        const container = range.commonAncestorContainer;
        
        // 查找选中区域内的高亮元素
        let highlights = [];
        if (container.nodeType === Node.ELEMENT_NODE) {
            highlights = container.querySelectorAll('.highlight');
        } else if (container.parentElement) {
            highlights = container.parentElement.querySelectorAll('.highlight');
        }
        
        highlights.forEach(highlight => {
            if (selection.containsNode(highlight, true)) {
                const parent = highlight.parentNode;
                while (highlight.firstChild) {
                    parent.insertBefore(highlight.firstChild, highlight);
                }
                parent.removeChild(highlight);
            }
        });
        
        selection.removeAllRanges();
        this.autoSave();
    }
    
    // 绑定高亮点击事件
    bindHighlightEvents() {
        document.querySelectorAll('.highlight').forEach(highlight => {
            highlight.addEventListener('click', (e) => {
                e.stopPropagation();
                if (!this.isEditMode) {
                    this.showAnnotationModal(highlight);
                }
            });
        });
    }
    
    // 显示批注模态框
    showAnnotationModal(highlightElement) {
        const modal = document.getElementById('annotationModal');
        const textarea = document.getElementById('annotationText');
        
        // 获取现有批注
        const highlightId = highlightElement.dataset.id;
        const annotation = this.annotations[highlightId] || '';
        
        textarea.value = annotation;
        modal.classList.add('active');
        modal.dataset.highlightId = highlightId;
        
        // 在阅读模式下显示批注内容
        if (!this.isEditMode) {
            this.showAnnotationInPanel(highlightElement);
        }
        
        setTimeout(() => textarea.focus(), 100);
    }
    
    // 在右侧面板显示批注
    showAnnotationInPanel(highlightElement) {
        const container = document.getElementById('annotationsContainer');
        const highlightId = highlightElement.dataset.id;
        const annotation = this.annotations[highlightId] || '';
        const highlightedText = highlightElement.dataset.text || highlightElement.textContent;
        
        container.innerHTML = `
            <div class="annotation-item">
                <div class="highlighted-text">"${highlightedText}"</div>
                <div class="annotation-text">${annotation || '暂无批注'}</div>
            </div>
        `;
    }
    
    // 保存批注
    saveAnnotation() {
        const modal = document.getElementById('annotationModal');
        const textarea = document.getElementById('annotationText');
        const highlightId = modal.dataset.highlightId;
        
        if (highlightId) {
            this.annotations[highlightId] = textarea.value;
            this.saveAnnotations();
        }
        
        this.closeAnnotationModal();
    }
    
    // 关闭批注模态框
    closeAnnotationModal() {
        const modal = document.getElementById('annotationModal');
        modal.classList.remove('active');
        delete modal.dataset.highlightId;
    }
    
    // 切换思路显示
    toggleThinking() {
        const thinkingContent = document.getElementById('thinkingContent');
        const btn = document.getElementById('showThinkingBtn');
        
        if (thinkingContent.classList.contains('hidden')) {
            thinkingContent.classList.remove('hidden');
            btn.textContent = '隐藏思路';
        } else {
            thinkingContent.classList.add('hidden');
            btn.textContent = '显示思路';
        }
    }
    
    // 渲染题目列表
    renderQuestionsList() {
        const container = document.getElementById('questionsList');
        const filteredQuestions = this.getFilteredQuestions();
        
        if (filteredQuestions.length === 0) {
            container.innerHTML = '<div class="no-questions">暂无题目，点击"新建题目"开始学习</div>';
            return;
        }
        
        container.innerHTML = filteredQuestions.map(question => {
            const canDelete = this.canDeleteQuestion(question);
            const deleteButton = canDelete ? 
                `<button class="delete-btn" data-id="${question.id}" title="删除题目">
                    <i class="fas fa-trash"></i>
                </button>` : '';
            
            return `
                <div class="question-card" data-id="${question.id}">
                    <div class="card-header">
                        <h3>${question.title}</h3>
                        ${deleteButton}
                    </div>
                    <div class="meta">
                        <span class="category-badge">${question.category}</span>
                        <span class="subcategory-badge">${question.subcategory}</span>
                        ${this.getOwnerBadge(question)}
                    </div>
                    <div class="preview">${this.getPreviewText(question.content)}</div>
                    <div class="question-actions">
                        <small>更新时间: ${new Date(question.updatedAt).toLocaleDateString()}</small>
                    </div>
                </div>
            `;
        }).join('');
        
        // 绑定点击事件
        container.querySelectorAll('.question-card').forEach(card => {
            card.addEventListener('click', (e) => {
                // 如果点击的是删除按钮，不触发卡片点击事件
                if (e.target.closest('.delete-btn')) {
                    return;
                }
                
                const questionId = card.dataset.id;
                const question = this.questions.find(q => q.id === questionId);
                if (question) {
                    this.showQuestionDetail(question);
                }
            });
        });
        
        // 绑定删除按钮事件
        container.querySelectorAll('.delete-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                e.stopPropagation(); // 阻止事件冒泡
                const questionId = btn.dataset.id;
                this.deleteQuestionById(questionId);
            });
        });
    }
    
    // 获取过滤后的题目
    getFilteredQuestions() {
        const searchTerm = document.getElementById('searchInput').value.toLowerCase();
        const categoryFilter = document.getElementById('categoryFilter').value;
        const subcategoryFilter = document.getElementById('subcategoryFilter').value;
        
        return this.questions.filter(question => {
            // 权限检查：只显示用户有权限查看的题目
            if (!this.canViewQuestion(question)) {
                return false;
            }
            
            const matchesSearch = !searchTerm || 
                question.title.toLowerCase().includes(searchTerm) ||
                question.content.toLowerCase().includes(searchTerm);
            
            const matchesCategory = !categoryFilter || question.category === categoryFilter;
            const matchesSubcategory = !subcategoryFilter || question.subcategory === subcategoryFilter;
            
            return matchesSearch && matchesCategory && matchesSubcategory;
        });
    }
    
    // 更新子分类过滤器
    updateSubcategoryFilter() {
        const categoryFilter = document.getElementById('categoryFilter').value;
        const subcategoryFilter = document.getElementById('subcategoryFilter');
        
        const subcategories = {
            '申论': ['概括归纳', '提出对策', '分析原因', '综合分析', '公文写作', '大作文'],
            '行测': ['政治常识', '常识', '言语', '数量', '判断', '资料']
        };
        
        subcategoryFilter.innerHTML = '<option value="">所有子分类</option>';
        
        if (categoryFilter && subcategories[categoryFilter]) {
            subcategories[categoryFilter].forEach(sub => {
                subcategoryFilter.innerHTML += `<option value="${sub}">${sub}</option>`;
            });
        }
    }
    
    // 过滤题目
    filterQuestions() {
        this.renderQuestionsList();
    }
    
    // 获取预览文本
    getPreviewText(content) {
        const tempDiv = document.createElement('div');
        tempDiv.innerHTML = content;
        const text = tempDiv.textContent || tempDiv.innerText || '';
        return text.length > 100 ? text.substring(0, 100) + '...' : text;
    }
    
    getOwnerBadge(question) {
        const currentUserId = window.authManager?.user?.id;
        const isAdmin = window.authManager?.isAdmin();
        
        if (!currentUserId) {
            return '';
        }
        
        // 如果是管理员，显示详细的创建者信息
        if (isAdmin) {
            if (question.ownerId && question.ownerId !== currentUserId) {
                return `<span class="owner-badge">用户: ${question.ownerId}</span>`;
            } else if (question.createdBy && question.createdBy !== currentUserId) {
                return `<span class="owner-badge">创建者: ${question.createdBy}</span>`;
            }
        } else {
            // 普通用户只显示是否为他人创建
            if (question.createdBy && question.createdBy !== currentUserId) {
                return '<span class="owner-badge">他人创建</span>';
            }
        }
        
        return '';
    }
    
    // 添加到历史记录
    addToHistory(question) {
        // 移除已存在的记录
        this.history = this.history.filter(h => h.id !== question.id);
        
        // 添加到开头
        this.history.unshift({
            id: question.id,
            title: question.title,
            category: question.category,
            subcategory: question.subcategory,
            accessTime: new Date().toISOString()
        });
        
        // 限制历史记录数量
        if (this.history.length > 10) {
            this.history = this.history.slice(0, 10);
        }
        
        this.saveHistory();
        this.renderHistory();
    }
    
    // 渲染历史记录
    renderHistory() {
        const container = document.getElementById('historyList');
        
        if (this.history.length === 0) {
            container.innerHTML = '<li class="no-history">暂无历史记录</li>';
            return;
        }
        
        container.innerHTML = this.history.map(item => `
            <li data-id="${item.id}">
                <div class="history-title">${item.title}</div>
                <div class="history-meta">${item.category} - ${item.subcategory}</div>
            </li>
        `).join('');
        
        // 绑定点击事件
        container.querySelectorAll('li[data-id]').forEach(item => {
            item.addEventListener('click', () => {
                const questionId = item.dataset.id;
                const question = this.questions.find(q => q.id === questionId);
                if (question) {
                    this.showQuestionDetail(question);
                }
            });
        });
    }
    
    // 添加标签
    addTag() {
        const input = document.getElementById('newTag');
        const tagName = input.value.trim();
        
        if (tagName && !this.tags.includes(tagName)) {
            this.tags.push(tagName);
            this.saveTags();
            this.renderTags();
            input.value = '';
        }
    }
    
    // 渲染标签
    renderTags() {
        const container = document.getElementById('tagsList');
        
        container.innerHTML = this.tags.map(tag => `
            <span class="tag" data-tag="${tag}">${tag}</span>
        `).join('');
        
        // 绑定点击事件
        container.querySelectorAll('.tag').forEach(tagEl => {
            tagEl.addEventListener('click', () => {
                // 可以实现标签过滤功能
                console.log('点击标签:', tagEl.dataset.tag);
            });
        });
    }
    
    // 自动保存设置
    setupAutoSave() {
        const editableElements = document.querySelectorAll('.editable-content');
        
        editableElements.forEach(element => {
            element.addEventListener('input', () => {
                this.autoSave();
            });
        });
    }
    
    // 自动保存
    autoSave() {
        if (!this.currentQuestion) return;
        
        clearTimeout(this.autoSaveTimer);
        this.autoSaveTimer = setTimeout(() => {
            this.saveCurrentQuestion();
        }, 1000); // 1秒后保存
    }
    
    // 保存当前题目
    async saveCurrentQuestion() {
        if (!this.currentQuestion) return;
        
        // 更新题目内容
        this.currentQuestion.content = document.getElementById('questionContent').innerHTML;
        this.currentQuestion.summary = document.getElementById('summaryContent').innerHTML;
        this.currentQuestion.example = document.getElementById('exampleContent').innerHTML;
        this.currentQuestion.thinking = document.getElementById('thinkingContent').innerHTML;
        this.currentQuestion.notes = document.getElementById('notesContent').innerHTML;
        this.currentQuestion.updatedAt = new Date().toISOString();
        
        // 保存到本地存储
        this.saveQuestions();
        
        // 如果启用云端同步，保存到云端
        if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
            try {
                await window.authManager.apiRequest('/data/questions', 'POST', {
                    question: this.currentQuestion
                });
            } catch (error) {
                console.warn('云端保存失败，仅保存到本地:', error.message);
            }
        }
        
        console.log('自动保存完成');
    }
    
    // 根据ID删除题目
    async deleteQuestionById(questionId) {
        const question = this.questions.find(q => q.id === questionId);
        if (!question) {
            alert('题目不存在');
            return;
        }
        
        // 确认删除
        const confirmDelete = confirm(`确定要删除题目 "${question.title}" 吗？\n\n此操作不可撤销！`);
        if (!confirmDelete) {
            return;
        }
        
        try {
            // 如果启用云端同步且已登录，先删除云端数据
            if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
                try {
                    await window.authManager.apiRequest(`/data/questions/${questionId}`, 'DELETE');
                } catch (error) {
                    console.warn('云端删除失败:', error.message);
                    // 继续执行本地删除
                }
            }
            
            // 从题目列表中删除
            this.questions = this.questions.filter(q => q.id !== questionId);
            
            // 从历史记录中删除
            this.history = this.history.filter(h => h.id !== questionId);
            
            // 删除相关的批注数据
            const annotationKey = `studySystem_annotations_${questionId}`;
            localStorage.removeItem(annotationKey);
            
            // 保存更新后的数据
            await this.saveQuestions();
            await this.saveHistory();
            
            // 重新渲染题目列表
            this.renderQuestionsList();
            this.renderHistory();
            
            // 显示成功消息
            alert('题目删除成功！');
            
        } catch (error) {
            console.error('删除题目时出错:', error);
            alert('删除题目失败，请重试');
        }
    }
    
    // 删除当前题目
    async deleteCurrentQuestion() {
        if (!this.currentQuestion) {
            alert('没有选中的题目可以删除');
            return;
        }
        
        // 确认删除
        const confirmDelete = confirm(`确定要删除题目 "${this.currentQuestion.title}" 吗？\n\n此操作不可撤销！`);
        if (!confirmDelete) {
            return;
        }
        
        try {
            // 如果启用云端同步且已登录，先删除云端数据
            if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
                try {
                    await window.authManager.apiRequest(`/data/questions/${this.currentQuestion.id}`, 'DELETE');
                } catch (error) {
                    console.warn('云端删除失败:', error.message);
                    // 继续执行本地删除
                }
            }
            
            // 从题目列表中删除
            this.questions = this.questions.filter(q => q.id !== this.currentQuestion.id);
            
            // 从历史记录中删除
            this.history = this.history.filter(h => h.id !== this.currentQuestion.id);
            
            // 删除相关的批注数据
            const annotationKey = `studySystem_annotations_${this.currentQuestion.id}`;
            localStorage.removeItem(annotationKey);
            
            // 保存更新后的数据
            await this.saveQuestions();
            await this.saveHistory();
            
            // 显示成功消息
            alert('题目删除成功！');
            
            // 返回题目列表
            this.currentQuestion = null;
            this.showQuestionsList();
            
        } catch (error) {
            console.error('删除题目时出错:', error);
            alert('删除题目失败，请重试');
        }
    }
    
    // 数据持久化方法
    async saveQuestions() {
        localStorage.setItem('studySystem_questions', JSON.stringify(this.questions));
        
        // 云端同步
        if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
            try {
                await window.authManager.apiRequest('/data/questions/batch', 'POST', {
                    questions: this.questions
                });
            } catch (error) {
                console.warn('云端同步失败:', error.message);
            }
        }
    }
    
    async loadQuestions() {
        try {
            if (this.cloudSyncEnabled && window.authManager?.isLoggedIn()) {
                // 管理员可以查看所有题目，普通用户只能查看自己的题目
                const endpoint = window.authManager?.isAdmin() ? '/api/admin/questions' : '/api/questions';
                
                const response = await window.authManager.apiRequest(endpoint, 'GET');
                
                if (response) {
                    this.questions = response;
                } else {
                    console.error('加载云端题目失败');
                    this.loadLocalQuestions();
                }
            } else {
                this.loadLocalQuestions();
            }
            
            this.renderQuestionsList();
        } catch (error) {
            console.error('加载题目失败:', error);
            this.loadLocalQuestions();
            this.renderQuestionsList();
        }
    }
    
    loadLocalQuestions() {
        const saved = localStorage.getItem('studySystem_questions');
        return saved ? JSON.parse(saved) : [];
    }
    
    async saveHistory() {
        localStorage.setItem('studySystem_history', JSON.stringify(this.history));
        
        // 云端同步
        if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
            try {
                await window.authManager.apiRequest('/data/history', 'POST', {
                    history: this.history
                });
            } catch (error) {
                console.warn('历史记录云端同步失败:', error.message);
            }
        }
    }
    
    loadHistory() {
        const saved = localStorage.getItem('studySystem_history');
        return saved ? JSON.parse(saved) : [];
    }
    
    async saveTags() {
        localStorage.setItem('studySystem_tags', JSON.stringify(this.tags));
        
        // 云端同步
        if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
            try {
                await window.authManager.apiRequest('/data/tags', 'POST', {
                    tags: this.tags
                });
            } catch (error) {
                console.warn('标签云端同步失败:', error.message);
            }
        }
    }
    
    loadTags() {
        const saved = localStorage.getItem('studySystem_tags');
        return saved ? JSON.parse(saved) : ['重要', '难点', '易错', '常考'];
    }
    
    async saveAnnotations() {
        if (this.currentQuestion) {
            const key = `studySystem_annotations_${this.currentQuestion.id}`;
            localStorage.setItem(key, JSON.stringify(this.annotations));
            
            // 云端同步
            if (this.cloudSyncEnabled && window.authManager && window.authManager.isLoggedIn()) {
                try {
                    await window.authManager.apiRequest(`/data/annotations/${this.currentQuestion.id}`, 'POST', {
                        annotations: this.annotations
                    });
                } catch (error) {
                    console.warn('批注云端同步失败:', error.message);
                }
            }
        }
    }
    
    loadAnnotations(questionId) {
        const key = `studySystem_annotations_${questionId}`;
        const saved = localStorage.getItem(key);
        this.annotations = saved ? JSON.parse(saved) : {};
        
        // 根据当前模式决定是否显示批注
        if (!this.isEditMode) {
            this.showAllAnnotations();
        } else {
            // 清空右侧批注面板
            document.getElementById('annotationsContainer').innerHTML = 
                '<div class="no-annotations">点击高亮文字查看批注</div>';
        }
    }
    
    // 显示所有批注
    showAllAnnotations() {
        const container = document.getElementById('annotationsContainer');
        const highlights = document.querySelectorAll('.highlight');
        
        if (highlights.length === 0 || Object.keys(this.annotations).length === 0) {
            container.innerHTML = '<div class="no-annotations">暂无批注内容</div>';
            return;
        }
        
        let annotationsHtml = '';
        highlights.forEach(highlight => {
            const highlightId = highlight.dataset.id;
            const annotation = this.annotations[highlightId];
            
            if (annotation && annotation.trim() !== '') {
                const highlightedText = highlight.dataset.text || highlight.textContent;
                const colorClass = highlight.className.split(' ').find(cls => 
                    ['yellow', 'green', 'blue', 'red'].includes(cls)
                ) || 'yellow';
                
                annotationsHtml += `
                    <div class="annotation-item" data-highlight-id="${highlightId}">
                        <div class="annotation-header">
                            <span class="highlight-indicator ${colorClass}"></span>
                            <small class="annotation-index">#${highlightId.slice(-4)}</small>
                        </div>
                        <div class="highlighted-text">"${highlightedText}"</div>
                        <div class="annotation-text">${annotation}</div>
                    </div>
                `;
            }
        });
        
        if (annotationsHtml === '') {
            container.innerHTML = '<div class="no-annotations">暂无批注内容</div>';
        } else {
            container.innerHTML = annotationsHtml;
            
            // 绑定批注项点击事件，点击时高亮对应的文字
            container.querySelectorAll('.annotation-item').forEach(item => {
                item.addEventListener('click', () => {
                    const highlightId = item.dataset.highlightId;
                    this.highlightCorrespondingText(highlightId);
                });
            });
        }
    }
    
    // 高亮对应的文字
    highlightCorrespondingText(highlightId) {
        // 移除之前的临时高亮
        document.querySelectorAll('.temp-highlight').forEach(el => {
            el.classList.remove('temp-highlight');
        });
        
        // 找到对应的高亮元素并添加临时高亮效果
        const targetHighlight = document.querySelector(`[data-id="${highlightId}"]`);
        if (targetHighlight) {
            targetHighlight.classList.add('temp-highlight');
            targetHighlight.scrollIntoView({ behavior: 'smooth', block: 'center' });
            
            // 3秒后移除临时高亮
            setTimeout(() => {
                targetHighlight.classList.remove('temp-highlight');
            }, 3000);
        }
    }
}

// 初始化应用
document.addEventListener('DOMContentLoaded', () => {
    window.studySystem = new StudySystem();
});

// 导出功能（可选）
function exportData() {
    const data = {
        questions: JSON.parse(localStorage.getItem('studySystem_questions') || '[]'),
        history: JSON.parse(localStorage.getItem('studySystem_history') || '[]'),
        tags: JSON.parse(localStorage.getItem('studySystem_tags') || '[]')
    };
    
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'study_system_backup.json';
    a.click();
    URL.revokeObjectURL(url);
}

// 导入功能（可选）
function importData(file) {
    const reader = new FileReader();
    reader.onload = (e) => {
        try {
            const data = JSON.parse(e.target.result);
            
            if (data.questions) {
                localStorage.setItem('studySystem_questions', JSON.stringify(data.questions));
            }
            if (data.history) {
                localStorage.setItem('studySystem_history', JSON.stringify(data.history));
            }
            if (data.tags) {
                localStorage.setItem('studySystem_tags', JSON.stringify(data.tags));
            }
            
            location.reload(); // 重新加载页面
        } catch (error) {
            alert('导入失败：文件格式不正确');
        }
    };
    reader.readAsText(file);
}