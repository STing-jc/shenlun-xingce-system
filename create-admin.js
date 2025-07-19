#!/usr/bin/env node

/**
 * 创建新管理员账户脚本
 * 使用方法: node create-admin.js <用户名> <邮箱> <密码>
 * 示例: node create-admin.js newadmin admin@example.com mypassword123
 */

const bcrypt = require('bcryptjs');
const fs = require('fs').promises;
const path = require('path');

const USERS_FILE = path.join(__dirname, 'data/users.json');

// 读取用户数据
async function readUsers() {
    try {
        const data = await fs.readFile(USERS_FILE, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        console.log('用户文件不存在，将创建新文件');
        return [];
    }
}

// 写入用户数据
async function writeUsers(users) {
    // 确保data目录存在
    const dataDir = path.dirname(USERS_FILE);
    try {
        await fs.access(dataDir);
    } catch {
        await fs.mkdir(dataDir, { recursive: true });
    }
    
    await fs.writeFile(USERS_FILE, JSON.stringify(users, null, 2));
}

// 创建新管理员
async function createAdmin(username, email, password) {
    try {
        // 验证输入
        if (!username || !email || !password) {
            throw new Error('用户名、邮箱和密码都是必填项');
        }
        
        if (password.length < 6) {
            throw new Error('密码长度至少6位');
        }
        
        // 验证邮箱格式
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(email)) {
            throw new Error('邮箱格式不正确');
        }
        
        const users = await readUsers();
        
        // 检查用户名和邮箱是否已存在
        const existingUser = users.find(u => u.username === username || u.email === email);
        if (existingUser) {
            throw new Error('用户名或邮箱已存在');
        }
        
        // 加密密码
        const hashedPassword = await bcrypt.hash(password, 10);
        
        // 创建新管理员
        const newAdmin = {
            id: `admin_${Date.now()}`,
            username,
            email,
            password: hashedPassword,
            role: 'admin',
            createdAt: new Date().toISOString(),
            lastLogin: null,
            isActive: true
        };
        
        users.push(newAdmin);
        await writeUsers(users);
        
        console.log('✅ 管理员账户创建成功！');
        console.log('📋 账户信息:');
        console.log(`   用户名: ${username}`);
        console.log(`   邮箱: ${email}`);
        console.log(`   角色: 管理员`);
        console.log(`   创建时间: ${newAdmin.createdAt}`);
        console.log(`   账户ID: ${newAdmin.id}`);
        console.log('');
        console.log('🔐 现在可以使用以下信息登录:');
        console.log(`   用户名: ${username}`);
        console.log(`   密码: ${password}`);
        
    } catch (error) {
        console.error('❌ 创建管理员失败:', error.message);
        process.exit(1);
    }
}

// 列出所有用户
async function listUsers() {
    try {
        const users = await readUsers();
        
        if (users.length === 0) {
            console.log('📝 暂无用户数据');
            return;
        }
        
        console.log('📋 当前用户列表:');
        console.log('=' .repeat(80));
        
        users.forEach((user, index) => {
            console.log(`${index + 1}. ${user.username}`);
            console.log(`   邮箱: ${user.email}`);
            console.log(`   角色: ${user.role === 'admin' ? '管理员' : '普通用户'}`);
            console.log(`   状态: ${user.isActive ? '激活' : '禁用'}`);
            console.log(`   创建时间: ${user.createdAt}`);
            console.log(`   最后登录: ${user.lastLogin || '从未登录'}`);
            console.log('-'.repeat(40));
        });
        
    } catch (error) {
        console.error('❌ 获取用户列表失败:', error.message);
    }
}

// 主函数
async function main() {
    const args = process.argv.slice(2);
    
    if (args.length === 0 || args[0] === '--help' || args[0] === '-h') {
        console.log('🔧 创建管理员账户工具');
        console.log('');
        console.log('使用方法:');
        console.log('  node create-admin.js <用户名> <邮箱> <密码>     # 创建新管理员');
        console.log('  node create-admin.js --list                    # 列出所有用户');
        console.log('  node create-admin.js --help                    # 显示帮助');
        console.log('');
        console.log('示例:');
        console.log('  node create-admin.js newadmin admin@example.com mypassword123');
        console.log('  node create-admin.js --list');
        return;
    }
    
    if (args[0] === '--list' || args[0] === '-l') {
        await listUsers();
        return;
    }
    
    if (args.length !== 3) {
        console.error('❌ 参数错误！需要提供用户名、邮箱和密码');
        console.log('使用 node create-admin.js --help 查看帮助');
        process.exit(1);
    }
    
    const [username, email, password] = args;
    await createAdmin(username, email, password);
}

// 运行主函数
if (require.main === module) {
    main().catch(error => {
        console.error('❌ 程序执行失败:', error.message);
        process.exit(1);
    });
}

module.exports = { createAdmin, listUsers };