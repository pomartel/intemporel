const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const model = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../CalendarModel.js'), 'utf8'), model);
const config = model.parseConfigResult(`{
  // URLs contain slash characters, not comments.
  "calendars": [{"url":"https://example.test/a", "emails":[" ME@Example.Test "],},],
}`);
assert.equal(config.error, '');
assert.equal(config.calendars[0].emails[0], 'me@example.test');
assert.equal(model.parseConfigResult('{"calendars":[{"url":"https://example.test/a"}]}').calendars[0].emails.length, 0);
assert.equal(model.parseConfigResult('{"calendars":[{"url":"webcal://example.test/a"}]}').calendars[0].url, 'https://example.test/a');
assert.equal(model.parseConfigResult('{"calendars":[{"url":"file:///tmp/a"}]}').error, '');
assert.notEqual(model.parseConfigResult('{"calendars":[{"url":"https://example.test/a"},{"url":"https://example.test/a"}]}').error, '');
assert.notEqual(model.parseConfigResult('{"calendars":false}').error, '');
assert.notEqual(model.parseConfigResult('invalid').error, '');
console.log('Configuration helper tests passed');
