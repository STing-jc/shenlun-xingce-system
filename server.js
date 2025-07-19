const express = require('express');
const path = require('path');
const cors = require('cors');
const { router: authRouter } = require('./api/auth');
const dataRouter = require('./api/data');

const app = express();
const PORT = process.env.PORT || 3000;

// 中间件设置
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// API路由
app.use('/api/auth', authRouter);
app.use('/api/data', dataRouter);

// 健康检查
app.get('/api/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

// 设置静态文件目录
app.use(express.static(path.join(__dirname)));

// 处理所有其他路由，返回index.html（单页应用）
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'index.html'));
});

// 启动服务器
app.listen(PORT, '0.0.0.0', () => {
    console.log(`申论行测学习系统已启动`);
    console.log(`服务器运行在: http://localhost:${PORT}`);
    console.log(`外网访问: http://0.0.0.0:${PORT}`);
});

// 优雅关闭
process.on('SIGTERM', () => {
    console.log('收到SIGTERM信号，正在关闭服务器...');
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('收到SIGINT信号，正在关闭服务器...');
    process.exit(0);
});