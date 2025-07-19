const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const fs = require('fs').promises;
const path = require('path');

const router = express.Router();
const JWT_SECRET = process.env.JWT_SECRET || 'study_system_secret_key_2024';
const USERS_FILE = path.join(__dirname, '../data/users.json');

// 确保用户文件存在
async function ensureUsersFile() {
    try {
        await fs.access(USERS_FILE);
    } catch (error) {
        // 创建默认管理员账户
        const defaultAdmin = {
            id: 'admin_001',
            username: 'admin',
            email: 'admin@study.com',
            password: await bcrypt.hash('admin123', 10),
            role: 'admin',
            createdAt: new Date().toISOString(),
            lastLogin: null,
            isActive: true
        };
        
        await fs.writeFile(USERS_FILE, JSON.stringify([defaultAdmin], null, 2));
        console.log('已创建默认管理员账户: admin/admin123');
    }
}

// 读取用户数据
async function readUsers() {
    try {
        const data = await fs.readFile(USERS_FILE, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        return [];
    }
}

// 写入用户数据
async function writeUsers(users) {
    await fs.writeFile(USERS_FILE, JSON.stringify(users, null, 2));
}

// 中间件：验证JWT令牌
function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: '访问令牌缺失' });
    }

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: '令牌无效' });
        }
        req.user = user;
        next();
    });
}

// 中间件：验证管理员权限
function requireAdmin(req, res, next) {
    if (req.user.role !== 'admin') {
        return res.status(403).json({ error: '需要管理员权限' });
    }
    next();
}

// 用户注册
router.post('/register', async (req, res) => {
    try {
        const { username, email, password } = req.body;
        
        if (!username || !email || !password) {
            return res.status(400).json({ error: '用户名、邮箱和密码都是必填项' });
        }
        
        if (password.length < 6) {
            return res.status(400).json({ error: '密码长度至少6位' });
        }
        
        const users = await readUsers();
        
        // 检查用户名和邮箱是否已存在
        const existingUser = users.find(u => u.username === username || u.email === email);
        if (existingUser) {
            return res.status(400).json({ error: '用户名或邮箱已存在' });
        }
        
        // 创建新用户
        const hashedPassword = await bcrypt.hash(password, 10);
        const newUser = {
            id: `user_${Date.now()}`,
            username,
            email,
            password: hashedPassword,
            role: 'user', // 默认为普通用户
            createdAt: new Date().toISOString(),
            lastLogin: null,
            isActive: true
        };
        
        users.push(newUser);
        await writeUsers(users);
        
        // 返回用户信息（不包含密码）
        const { password: _, ...userInfo } = newUser;
        res.status(201).json({ 
            message: '注册成功', 
            user: userInfo 
        });
        
    } catch (error) {
        console.error('注册错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 用户登录
router.post('/login', async (req, res) => {
    try {
        const { username, password } = req.body;
        
        if (!username || !password) {
            return res.status(400).json({ error: '用户名和密码都是必填项' });
        }
        
        const users = await readUsers();
        const user = users.find(u => u.username === username && u.isActive);
        
        if (!user) {
            return res.status(401).json({ error: '用户名或密码错误' });
        }
        
        const isValidPassword = await bcrypt.compare(password, user.password);
        if (!isValidPassword) {
            return res.status(401).json({ error: '用户名或密码错误' });
        }
        
        // 更新最后登录时间
        user.lastLogin = new Date().toISOString();
        await writeUsers(users);
        
        // 生成JWT令牌
        const token = jwt.sign(
            { 
                id: user.id, 
                username: user.username, 
                role: user.role 
            },
            JWT_SECRET,
            { expiresIn: '24h' }
        );
        
        // 返回用户信息和令牌
        const { password: _, ...userInfo } = user;
        res.json({ 
            message: '登录成功', 
            token, 
            user: userInfo 
        });
        
    } catch (error) {
        console.error('登录错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 获取当前用户信息
router.get('/me', authenticateToken, async (req, res) => {
    try {
        const users = await readUsers();
        const user = users.find(u => u.id === req.user.id);
        
        if (!user) {
            return res.status(404).json({ error: '用户不存在' });
        }
        
        const { password: _, ...userInfo } = user;
        res.json(userInfo);
        
    } catch (error) {
        console.error('获取用户信息错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 管理员：获取所有用户
router.get('/users', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const users = await readUsers();
        const usersInfo = users.map(({ password, ...user }) => user);
        res.json(usersInfo);
        
    } catch (error) {
        console.error('获取用户列表错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 管理员：更新用户状态
router.put('/users/:userId/status', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { userId } = req.params;
        const { isActive } = req.body;
        
        const users = await readUsers();
        const userIndex = users.findIndex(u => u.id === userId);
        
        if (userIndex === -1) {
            return res.status(404).json({ error: '用户不存在' });
        }
        
        users[userIndex].isActive = isActive;
        await writeUsers(users);
        
        res.json({ message: '用户状态更新成功' });
        
    } catch (error) {
        console.error('更新用户状态错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 管理员：删除用户
router.delete('/users/:userId', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { userId } = req.params;
        
        const users = await readUsers();
        const filteredUsers = users.filter(u => u.id !== userId);
        
        if (filteredUsers.length === users.length) {
            return res.status(404).json({ error: '用户不存在' });
        }
        
        await writeUsers(filteredUsers);
        res.json({ message: '用户删除成功' });
        
    } catch (error) {
        console.error('删除用户错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 初始化用户文件
ensureUsersFile();

module.exports = { router, authenticateToken, requireAdmin };