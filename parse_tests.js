const fs = require('fs');
const lines = fs.readFileSync('test_output.json', 'utf-8').split('\n');
for (const line of lines) {
    if (!line.trim().startsWith('{')) continue;
    try {
        const ob = JSON.parse(line);
        if (ob.error) console.log(ob.error);
        if (ob.stackTrace) console.log(ob.stackTrace);
        if (ob.type === 'testDone' && ob.result === 'error') console.log('FAILED TEST ID:', ob.testID);
    } catch (e) { }
}
