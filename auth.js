// 用户认证和数据同步管理
class AuthManager {
    constructor() {
        this.token = localStorage.getItem('auth_token');
        this.user = JSON.parse(localStorage.getItem('user_info') || 'null');
        this.apiBase = '/api';
        this.isOnline = navigator.onLine;
        
        this.init();
    }
    
    init() {
        this.setupNetworkListeners();
        this.setupAuthUI();
        
        // 如果已登录，验证token有效性
        if (this.token) {
            this.validateToken();
        } else {
            this.showLoginForm();
        }
    }
    
    // 网络状态监听
    setupNetworkListeners() {
        window.addEventListener('online', () => {
            this.isOnline = true;
            this.showMessage('网络已连接，正在同步数据...', 'success');
            this.syncData();
        });
        
        window.addEventListener('offline', () => {
            this.isOnline = false;
            this.showMessage('网络已断开，将使用离线模式', 'warning');
        });
    }
    
    // 设置认证UI
    setupAuthUI() {
        // 创建登录模态框
        if (!document.getElementById('authModal')) {
            const authModal = document.createElement('div');
            authModal.id = 'authModal';
            authModal.className = 'auth-modal';
            authModal.innerHTML = `
                <div class="auth-modal-content">
                    <div class="auth-header">
                        <h2 id="authTitle">用户登录</h2>
                        <div class="auth-tabs">
                            <button id="loginTab" class="auth-tab active">登录</button>
                            <button id="registerTab" class="auth-tab">注册</button>
                        </div>
                    </div>
                    
                    <form id="authForm">
                        <div class="form-group">
                            <label for="username">用户名</label>
                            <input type="text" id="username" required>
                        </div>
                        
                        <div class="form-group" id="emailGroup" style="display: none;">
                            <label for="email">邮箱</label>
                            <input type="email" id="email">
                        </div>
                        
                        <div class="form-group">
                            <label for="password">密码</label>
                            <input type="password" id="password" required>
                        </div>
                        
                        <div class="form-group" id="confirmPasswordGroup" style="display: none;">
                            <label for="confirmPassword">确认密码</label>
                            <input type="password" id="confirmPassword">
                        </div>
                        
                        <button type="submit" id="authSubmit" class="btn btn-primary">登录</button>
                    </form>
                    
                    <div class="auth-footer">
                        <p id="authMessage"></p>
                        <div class="offline-mode">
                            <button id="offlineModeBtn" class="btn btn-secondary">离线模式</button>
                            <small>离线模式下数据仅保存在本地</small>
                        </div>
                    </div>
                </div>
            `;
            document.body.appendChild(authModal);
            
            this.bindAuthEvents();
        }
        
        // 创建用户信息显示区域
        if (!document.getElementById('userInfo')) {
            const userInfo = document.createElement('div');
            userInfo.id = 'userInfo';
            userInfo.className = 'user-info';
            userInfo.innerHTML = `
                <div class="user-avatar">
                    <i class="fas fa-user"></i>
                </div>
                <div class="user-details">
                    <span id="userName"></span>
                    <span id="userRole"></span>
                </div>
                <div class="user-actions">
                    <button id="syncBtn" class="btn btn-sm" title="同步数据">
                        <i class="fas fa-sync"></i>
                    </button>
                    <button id="logoutBtn" class="btn btn-sm" title="退出登录">
                        <i class="fas fa-sign-out-alt"></i>
                    </button>
                </div>
            `;
            
            // 插入到侧边栏顶部
            const sidebar = document.querySelector('.sidebar');
            sidebar.insertBefore(userInfo, sidebar.firstChild);
            
            this.bindUserInfoEvents();
        }
    }
    
    // 绑定认证相关事件
    bindAuthEvents() {
        const loginTab = document.getElementById('loginTab');
        const registerTab = document.getElementById('registerTab');
        const authForm = document.getElementById('authForm');
        const offlineModeBtn = document.getElementById('offlineModeBtn');
        
        loginTab.addEventListener('click', () => this.switchToLogin());
        registerTab.addEventListener('click', () => this.switchToRegister());
        authForm.addEventListener('submit', (e) => this.handleAuth(e));
        offlineModeBtn.addEventListener('click', () => this.enterOfflineMode());
    }
    
    // 绑定用户信息相关事件
    bindUserInfoEvents() {
        const syncBtn = document.getElementById('syncBtn');
        const logoutBtn = document.getElementById('logoutBtn');
        
        syncBtn.addEventListener('click', () => this.syncData());
        logoutBtn.addEventListener('click', () => this.logout());
    }
    
    // 切换到登录模式
    switchToLogin() {
        document.getElementById('loginTab').classList.add('active');
        document.getElementById('registerTab').classList.remove('active');
        document.getElementById('authTitle').textContent = '用户登录';
        document.getElementById('emailGroup').style.display = 'none';
        document.getElementById('confirmPasswordGroup').style.display = 'none';
        document.getElementById('authSubmit').textContent = '登录';
        document.getElementById('email').required = false;
        document.getElementById('confirmPassword').required = false;
    }
    
    // 切换到注册模式
    switchToRegister() {
        document.getElementById('registerTab').classList.add('active');
        document.getElementById('loginTab').classList.remove('active');
        document.getElementById('authTitle').textContent = '用户注册';
        document.getElementById('emailGroup').style.display = 'block';
        document.getElementById('confirmPasswordGroup').style.display = 'block';
        document.getElementById('authSubmit').textContent = '注册';
        document.getElementById('email').required = true;
        document.getElementById('confirmPassword').required = true;
    }
    
    // 处理登录/注册
    async handleAuth(e) {
        e.preventDefault();
        
        const isLogin = document.getElementById('loginTab').classList.contains('active');
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const email = document.getElementById('email').value;
        const confirmPassword = document.getElementById('confirmPassword').value;
        
        // 表单验证
        if (!isLogin) {
            if (password !== confirmPassword) {
                this.showAuthMessage('密码确认不匹配', 'error');
                return;
            }
            if (password.length < 6) {
                this.showAuthMessage('密码长度至少6位', 'error');
                return;
            }
        }
        
        try {
            const endpoint = isLogin ? '/auth/login' : '/auth/register';
            const data = isLogin ? { username, password } : { username, email, password };
            
            const response = await this.apiRequest(endpoint, 'POST', data);
            
            if (response.token) {
                this.token = response.token;
                this.user = response.user;
                
                localStorage.setItem('auth_token', this.token);
                localStorage.setItem('user_info', JSON.stringify(this.user));
                
                this.hideLoginForm();
                this.updateUserInfo();
                this.showMessage(response.message, 'success');
                
                // 登录后同步数据
                if (isLogin) {
                    this.syncData();
                }
            } else {
                this.showAuthMessage(response.message, 'success');
                if (!isLogin) {
                    // 注册成功后切换到登录
                    setTimeout(() => this.switchToLogin(), 1500);
                }
            }
            
        } catch (error) {
            this.showAuthMessage(error.message, 'error');
        }
    }
    
    // 验证token有效性
    async validateToken() {
        try {
            const response = await this.apiRequest('/auth/me', 'GET');
            this.user = response;
            localStorage.setItem('user_info', JSON.stringify(this.user));
            this.updateUserInfo();
            this.hideLoginForm();
        } catch (error) {
            // Token无效，清除本地存储
            this.logout(false);
        }
    }
    
    // 退出登录
    logout(showMessage = true) {
        this.token = null;
        this.user = null;
        localStorage.removeItem('auth_token');
        localStorage.removeItem('user_info');
        
        this.showLoginForm();
        this.updateUserInfo();
        
        if (showMessage) {
            this.showMessage('已退出登录', 'info');
        }
    }
    
    // 进入离线模式
    enterOfflineMode() {
        this.hideLoginForm();
        this.showMessage('已进入离线模式，数据仅保存在本地', 'info');
    }
    
    // 显示登录表单
    showLoginForm() {
        document.getElementById('authModal').style.display = 'flex';
        document.getElementById('userInfo').style.display = 'none';
    }
    
    // 隐藏登录表单
    hideLoginForm() {
        document.getElementById('authModal').style.display = 'none';
        document.getElementById('userInfo').style.display = 'flex';
    }
    
    // 更新用户信息显示
    updateUserInfo() {
        if (this.user) {
            document.getElementById('userName').textContent = this.user.username;
            document.getElementById('userRole').textContent = 
                this.user.role === 'admin' ? '管理员' : '普通用户';
            document.getElementById('userInfo').style.display = 'flex';
        } else {
            document.getElementById('userInfo').style.display = 'none';
        }
    }
    
    // 数据同步
    async syncData() {
        if (!this.token || !this.isOnline) {
            return;
        }
        
        try {
            // 显示同步状态
            const syncBtn = document.getElementById('syncBtn');
            const originalIcon = syncBtn.innerHTML;
            syncBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';
            
            // 获取本地数据
            const localData = {
                questions: JSON.parse(localStorage.getItem('studySystem_questions') || '[]'),
                history: JSON.parse(localStorage.getItem('studySystem_history') || '[]'),
                tags: JSON.parse(localStorage.getItem('studySystem_tags') || '[]')
            };
            
            // 获取所有批注
            const annotations = {};
            for (let i = 0; i < localStorage.length; i++) {
                const key = localStorage.key(i);
                if (key.startsWith('studySystem_annotations_')) {
                    const questionId = key.replace('studySystem_annotations_', '');
                    annotations[questionId] = JSON.parse(localStorage.getItem(key));
                }
            }
            localData.annotations = annotations;
            
            // 上传本地数据到云端
            if (localData.questions.length > 0 || localData.history.length > 0) {
                await this.apiRequest('/data/sync/upload', 'POST', localData);
            }
            
            // 从云端下载数据
            const cloudData = await this.apiRequest('/data/sync/download', 'GET');
            
            // 合并数据（云端数据优先）
            if (cloudData.questions) {
                localStorage.setItem('studySystem_questions', JSON.stringify(cloudData.questions));
            }
            if (cloudData.history) {
                localStorage.setItem('studySystem_history', JSON.stringify(cloudData.history));
            }
            if (cloudData.tags) {
                localStorage.setItem('studySystem_tags', JSON.stringify(cloudData.tags));
            }
            if (cloudData.annotations) {
                for (const [questionId, annotationData] of Object.entries(cloudData.annotations)) {
                    localStorage.setItem(`studySystem_annotations_${questionId}`, JSON.stringify(annotationData));
                }
            }
            
            // 恢复同步按钮
            syncBtn.innerHTML = originalIcon;
            this.showMessage('数据同步成功', 'success');
            
            // 刷新页面数据
            if (window.studySystem) {
                window.studySystem.questions = JSON.parse(localStorage.getItem('studySystem_questions') || '[]');
                window.studySystem.history = JSON.parse(localStorage.getItem('studySystem_history') || '[]');
                window.studySystem.tags = JSON.parse(localStorage.getItem('studySystem_tags') || '[]');
                window.studySystem.renderQuestionsList();
                window.studySystem.renderHistory();
                window.studySystem.renderTags();
            }
            
        } catch (error) {
            const syncBtn = document.getElementById('syncBtn');
            syncBtn.innerHTML = '<i class="fas fa-sync"></i>';
            this.showMessage('数据同步失败: ' + error.message, 'error');
        }
    }
    
    // API请求封装
    async apiRequest(endpoint, method = 'GET', data = null) {
        const url = this.apiBase + endpoint;
        const options = {
            method,
            headers: {
                'Content-Type': 'application/json'
            }
        };
        
        if (this.token) {
            options.headers['Authorization'] = `Bearer ${this.token}`;
        }
        
        if (data) {
            options.body = JSON.stringify(data);
        }
        
        const response = await fetch(url, options);
        const result = await response.json();
        
        if (!response.ok) {
            throw new Error(result.error || '请求失败');
        }
        
        return result;
    }
    
    // 显示认证消息
    showAuthMessage(message, type) {
        const messageEl = document.getElementById('authMessage');
        messageEl.textContent = message;
        messageEl.className = `auth-message ${type}`;
    }
    
    // 显示全局消息
    showMessage(message, type) {
        // 创建消息提示
        const messageEl = document.createElement('div');
        messageEl.className = `global-message ${type}`;
        messageEl.innerHTML = `
            <i class="fas fa-${type === 'success' ? 'check' : type === 'error' ? 'times' : 'info'}"></i>
            <span>${message}</span>
        `;
        
        document.body.appendChild(messageEl);
        
        // 3秒后自动移除
        setTimeout(() => {
            if (messageEl.parentNode) {
                messageEl.parentNode.removeChild(messageEl);
            }
        }, 3000);
    }
    
    // 检查是否已登录
    isLoggedIn() {
        return !!this.token;
    }
    
    // 检查是否是管理员
    isAdmin() {
        return this.user && this.user.role === 'admin';
    }
}

// 全局认证管理器实例
window.authManager = new AuthManager();