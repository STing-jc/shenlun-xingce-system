const express = require('express');
const fs = require('fs').promises;
const path = require('path');
const { authenticateToken, requireAdmin } = require('./auth');

const router = express.Router();

// 数据文件路径
const DATA_DIR = path.join(__dirname, '../data/users_data');
const QUESTIONS_DIR = path.join(DATA_DIR, 'questions');
const HISTORY_DIR = path.join(DATA_DIR, 'history');
const TAGS_DIR = path.join(DATA_DIR, 'tags');
const ANNOTATIONS_DIR = path.join(DATA_DIR, 'annotations');

// 确保目录存在
async function ensureDirectories() {
    const dirs = [DATA_DIR, QUESTIONS_DIR, HISTORY_DIR, TAGS_DIR, ANNOTATIONS_DIR];
    for (const dir of dirs) {
        try {
            await fs.access(dir);
        } catch (error) {
            await fs.mkdir(dir, { recursive: true });
        }
    }
}

// 获取用户数据文件路径
function getUserDataPath(userId, type) {
    const dirs = {
        questions: QUESTIONS_DIR,
        history: HISTORY_DIR,
        tags: TAGS_DIR,
        annotations: ANNOTATIONS_DIR
    };
    return path.join(dirs[type], `${userId}.json`);
}

// 读取用户数据
async function readUserData(userId, type) {
    try {
        const filePath = getUserDataPath(userId, type);
        const data = await fs.readFile(filePath, 'utf8');
        return JSON.parse(data);
    } catch (error) {
        return type === 'tags' ? ['重要', '难点', '易错', '常考'] : [];
    }
}

// 写入用户数据
async function writeUserData(userId, type, data) {
    const filePath = getUserDataPath(userId, type);
    await fs.writeFile(filePath, JSON.stringify(data, null, 2));
}

// 获取题目列表
router.get('/questions', authenticateToken, async (req, res) => {
    try {
        const questions = await readUserData(req.user.id, 'questions');
        res.json(questions);
    } catch (error) {
        console.error('获取题目列表错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 管理员获取所有用户的题目
router.get('/admin/questions', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const allQuestions = [];
        const dataDir = path.join(__dirname, '../data');
        
        // 读取所有用户的题目数据
        const userDirs = await fs.readdir(dataDir);
        for (const userDir of userDirs) {
            const userPath = path.join(dataDir, userDir);
            const stat = await fs.stat(userPath);
            
            if (stat.isDirectory()) {
                try {
                    const questionsPath = path.join(userPath, 'questions.json');
                    const questionsData = await fs.readFile(questionsPath, 'utf8');
                    const userQuestions = JSON.parse(questionsData);
                    
                    // 为每个题目添加用户信息
                    userQuestions.forEach(question => {
                        question.ownerId = userDir;
                        allQuestions.push(question);
                    });
                } catch (error) {
                    // 忽略不存在的文件或解析错误
                }
            }
        }
        
        res.json(allQuestions);
    } catch (error) {
        console.error('管理员获取所有题目错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 保存题目
router.post('/questions', authenticateToken, async (req, res) => {
    try {
        const { question } = req.body;
        
        if (!question || !question.title) {
            return res.status(400).json({ error: '题目数据不完整' });
        }
        
        const questions = await readUserData(req.user.id, 'questions');
        
        // 检查是否是新题目或更新现有题目
        const existingIndex = questions.findIndex(q => q.id === question.id);
        
        if (existingIndex >= 0) {
            // 权限检查：验证用户是否有权限修改这个题目
            const existingQuestion = questions[existingIndex];
            if (existingQuestion.createdBy && 
                existingQuestion.createdBy !== req.user.id && 
                !req.user.isAdmin) {
                return res.status(403).json({ 
                    error: '您没有权限修改此题目',
                    questionId: question.id 
                });
            }
            
            // 更新现有题目
            questions[existingIndex] = {
                ...question,
                updatedAt: new Date().toISOString()
            };
        } else {
            // 添加新题目
            question.id = question.id || `q_${Date.now()}`;
            question.createdAt = question.createdAt || new Date().toISOString();
            question.updatedAt = new Date().toISOString();
            question.createdBy = req.user.id; // 设置创建者
            questions.push(question);
        }
        
        await writeUserData(req.user.id, 'questions', questions);
        res.json({ message: '题目保存成功', question });
        
    } catch (error) {
        console.error('保存题目错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 批量保存题目
router.post('/questions/batch', authenticateToken, async (req, res) => {
    try {
        const { questions } = req.body;
        
        if (!Array.isArray(questions)) {
            return res.status(400).json({ error: '题目数据格式错误' });
        }
        
        // 获取现有题目
        const existingQuestions = await readUserData(req.user.id, 'questions');
        
        // 权限检查：验证用户是否有权限修改这些题目
        for (const question of questions) {
            if (question.id) {
                const existingQuestion = existingQuestions.find(q => q.id === question.id);
                if (existingQuestion) {
                    // 检查是否为题目创建者或管理员
                    if (existingQuestion.createdBy && 
                        existingQuestion.createdBy !== req.user.id && 
                        !req.user.isAdmin) {
                        return res.status(403).json({ 
                            error: '您没有权限修改此题目',
                            questionId: question.id 
                        });
                    }
                }
            }
            
            // 为新题目设置创建者
            if (!question.id || !existingQuestions.find(q => q.id === question.id)) {
                question.createdBy = req.user.id;
            }
        }
        
        await writeUserData(req.user.id, 'questions', questions);
        res.json({ message: '题目批量保存成功', count: questions.length });
        
    } catch (error) {
        console.error('批量保存题目错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 删除题目
router.delete('/questions/:questionId', authenticateToken, async (req, res) => {
    try {
        const { questionId } = req.params;
        
        // 首先从当前用户的数据中查找题目
        const userQuestions = await readUserData(req.user.id, 'questions');
        let questionToDelete = userQuestions.find(q => q.id === questionId);
        
        // 如果当前用户没有这个题目，且是管理员，则查找所有用户的题目
        if (!questionToDelete && req.user.isAdmin) {
            // 管理员可以删除任何用户的题目，需要查找题目的实际创建者
            const userDataDir = path.join(__dirname, '../data/users');
            try {
                const userDirs = await fs.readdir(userDataDir);
                
                for (const userId of userDirs) {
                    try {
                        const questions = await readUserData(userId, 'questions');
                        const foundQuestion = questions.find(q => q.id === questionId);
                        if (foundQuestion) {
                            questionToDelete = foundQuestion;
                            questionToDelete._originalUserId = userId; // 记录原始用户ID
                            break;
                        }
                    } catch (error) {
                        // 忽略读取单个用户数据的错误
                        continue;
                    }
                }
            } catch (error) {
                console.warn('查找题目时出错:', error);
            }
        }
        
        if (!questionToDelete) {
            return res.status(404).json({ error: '题目不存在' });
        }
        
        // 权限检查：验证用户是否有权限删除这个题目
        if (questionToDelete.createdBy && 
            questionToDelete.createdBy !== req.user.id && 
            !req.user.isAdmin) {
            return res.status(403).json({ 
                error: '您没有权限删除此题目',
                questionId: questionId 
            });
        }
        
        // 如果是管理员删除题目，需要从所有用户的数据中删除
        if (req.user.isAdmin) {
            await deleteQuestionFromAllUsers(questionId);
        } else {
            // 普通用户只删除自己的题目
            const filteredQuestions = userQuestions.filter(q => q.id !== questionId);
            await writeUserData(req.user.id, 'questions', filteredQuestions);
            
            // 删除相关的批注
            try {
                const annotationsPath = path.join(ANNOTATIONS_DIR, `${req.user.id}_${questionId}.json`);
                await fs.unlink(annotationsPath);
            } catch (error) {
                // 批注文件可能不存在，忽略错误
            }
        }
        
        res.json({ message: '题目删除成功' });
        
    } catch (error) {
        console.error('删除题目错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 从所有用户数据中删除指定题目（管理员功能）
async function deleteQuestionFromAllUsers(questionId) {
    const userDataDir = path.join(__dirname, '../data/users');
    
    try {
        const userDirs = await fs.readdir(userDataDir);
        
        for (const userId of userDirs) {
            try {
                // 删除题目
                const questions = await readUserData(userId, 'questions');
                const filteredQuestions = questions.filter(q => q.id !== questionId);
                
                if (filteredQuestions.length !== questions.length) {
                    await writeUserData(userId, 'questions', filteredQuestions);
                }
                
                // 删除历史记录中的相关条目
                const history = await readUserData(userId, 'history');
                const filteredHistory = history.filter(h => h.id !== questionId);
                
                if (filteredHistory.length !== history.length) {
                    await writeUserData(userId, 'history', filteredHistory);
                }
                
                // 删除相关的批注文件
                try {
                    const annotationsPath = path.join(ANNOTATIONS_DIR, `${userId}_${questionId}.json`);
                    await fs.unlink(annotationsPath);
                } catch (error) {
                    // 批注文件可能不存在，忽略错误
                }
                
            } catch (error) {
                console.warn(`处理用户 ${userId} 的数据时出错:`, error);
                // 继续处理其他用户
            }
        }
    } catch (error) {
        console.error('删除题目时遍历用户目录出错:', error);
        throw error;
    }
}

// 获取历史记录
router.get('/history', authenticateToken, async (req, res) => {
    try {
        const history = await readUserData(req.user.id, 'history');
        res.json(history);
    } catch (error) {
        console.error('获取历史记录错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 保存历史记录
router.post('/history', authenticateToken, async (req, res) => {
    try {
        const { history } = req.body;
        
        if (!Array.isArray(history)) {
            return res.status(400).json({ error: '历史记录数据格式错误' });
        }
        
        await writeUserData(req.user.id, 'history', history);
        res.json({ message: '历史记录保存成功' });
        
    } catch (error) {
        console.error('保存历史记录错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 获取标签
router.get('/tags', authenticateToken, async (req, res) => {
    try {
        const tags = await readUserData(req.user.id, 'tags');
        res.json(tags);
    } catch (error) {
        console.error('获取标签错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 保存标签
router.post('/tags', authenticateToken, async (req, res) => {
    try {
        const { tags } = req.body;
        
        if (!Array.isArray(tags)) {
            return res.status(400).json({ error: '标签数据格式错误' });
        }
        
        await writeUserData(req.user.id, 'tags', tags);
        res.json({ message: '标签保存成功' });
        
    } catch (error) {
        console.error('保存标签错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 获取批注
router.get('/annotations/:questionId', authenticateToken, async (req, res) => {
    try {
        const { questionId } = req.params;
        const filePath = path.join(ANNOTATIONS_DIR, `${req.user.id}_${questionId}.json`);
        
        try {
            const data = await fs.readFile(filePath, 'utf8');
            const annotations = JSON.parse(data);
            res.json(annotations);
        } catch (error) {
            res.json({}); // 返回空对象如果文件不存在
        }
        
    } catch (error) {
        console.error('获取批注错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 保存批注
router.post('/annotations/:questionId', authenticateToken, async (req, res) => {
    try {
        const { questionId } = req.params;
        const { annotations } = req.body;
        
        if (typeof annotations !== 'object') {
            return res.status(400).json({ error: '批注数据格式错误' });
        }
        
        const filePath = path.join(ANNOTATIONS_DIR, `${req.user.id}_${questionId}.json`);
        await fs.writeFile(filePath, JSON.stringify(annotations, null, 2));
        
        res.json({ message: '批注保存成功' });
        
    } catch (error) {
        console.error('保存批注错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 数据同步：从本地上传到云端
router.post('/sync/upload', authenticateToken, async (req, res) => {
    try {
        const { questions, history, tags, annotations } = req.body;
        
        // 保存各类数据
        if (questions) {
            await writeUserData(req.user.id, 'questions', questions);
        }
        if (history) {
            await writeUserData(req.user.id, 'history', history);
        }
        if (tags) {
            await writeUserData(req.user.id, 'tags', tags);
        }
        if (annotations) {
            // 保存所有题目的批注
            for (const [questionId, annotationData] of Object.entries(annotations)) {
                const filePath = path.join(ANNOTATIONS_DIR, `${req.user.id}_${questionId}.json`);
                await fs.writeFile(filePath, JSON.stringify(annotationData, null, 2));
            }
        }
        
        res.json({ 
            message: '数据同步成功',
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('数据同步错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 数据同步：从云端下载到本地
router.get('/sync/download', authenticateToken, async (req, res) => {
    try {
        const questions = await readUserData(req.user.id, 'questions');
        const history = await readUserData(req.user.id, 'history');
        const tags = await readUserData(req.user.id, 'tags');
        
        // 获取所有批注
        const annotations = {};
        try {
            const annotationFiles = await fs.readdir(ANNOTATIONS_DIR);
            const userAnnotationFiles = annotationFiles.filter(file => 
                file.startsWith(`${req.user.id}_`) && file.endsWith('.json')
            );
            
            for (const file of userAnnotationFiles) {
                const questionId = file.replace(`${req.user.id}_`, '').replace('.json', '');
                const filePath = path.join(ANNOTATIONS_DIR, file);
                const data = await fs.readFile(filePath, 'utf8');
                annotations[questionId] = JSON.parse(data);
            }
        } catch (error) {
            // 忽略批注读取错误
        }
        
        res.json({
            questions,
            history,
            tags,
            annotations,
            timestamp: new Date().toISOString()
        });
        
    } catch (error) {
        console.error('数据下载错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 获取数据统计
router.get('/stats', authenticateToken, async (req, res) => {
    try {
        const questions = await readUserData(req.user.id, 'questions');
        const history = await readUserData(req.user.id, 'history');
        const tags = await readUserData(req.user.id, 'tags');
        
        // 统计各分类题目数量
        const categoryStats = {};
        questions.forEach(q => {
            if (!categoryStats[q.category]) {
                categoryStats[q.category] = {};
            }
            if (!categoryStats[q.category][q.subcategory]) {
                categoryStats[q.category][q.subcategory] = 0;
            }
            categoryStats[q.category][q.subcategory]++;
        });
        
        res.json({
            totalQuestions: questions.length,
            totalHistory: history.length,
            totalTags: tags.length,
            categoryStats,
            lastUpdated: questions.length > 0 ? 
                Math.max(...questions.map(q => new Date(q.updatedAt || q.createdAt).getTime())) : null
        });
        
    } catch (error) {
        console.error('获取统计数据错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 获取分类配置（管理员功能）
router.get('/categories', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const configPath = path.join(__dirname, '../data/config.json');
        
        try {
            const configData = await fs.readFile(configPath, 'utf8');
            const config = JSON.parse(configData);
            res.json(config.categories || getDefaultCategories());
        } catch (error) {
            // 如果配置文件不存在，返回默认分类
            res.json(getDefaultCategories());
        }
        
    } catch (error) {
        console.error('获取分类配置错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 保存分类配置（管理员功能）
router.post('/categories', authenticateToken, requireAdmin, async (req, res) => {
    try {
        const { categories } = req.body;
        
        if (!categories || typeof categories !== 'object') {
            return res.status(400).json({ error: '分类数据格式错误' });
        }
        
        const configPath = path.join(__dirname, '../data/config.json');
        
        // 读取现有配置或创建新配置
        let config = {};
        try {
            const configData = await fs.readFile(configPath, 'utf8');
            config = JSON.parse(configData);
        } catch (error) {
            // 配置文件不存在，创建新的
        }
        
        config.categories = categories;
        config.updatedAt = new Date().toISOString();
        config.updatedBy = req.user.id;
        
        await fs.writeFile(configPath, JSON.stringify(config, null, 2));
        res.json({ message: '分类配置保存成功' });
        
    } catch (error) {
        console.error('保存分类配置错误:', error);
        res.status(500).json({ error: '服务器内部错误' });
    }
});

// 获取默认分类配置
function getDefaultCategories() {
    return {
        '申论': {
            name: '申论',
            icon: 'fas fa-file-alt',
            subcategories: ['概括归纳', '提出对策', '分析原因', '综合分析', '公文写作', '大作文']
        },
        '行测': {
            name: '行测',
            icon: 'fas fa-calculator',
            subcategories: ['政治常识', '常识', '言语', '数量', '判断', '资料']
        }
    };
}

// 初始化时确保目录存在
ensureDirectories();

module.exports = router;