import os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
files={
 'Sources/Models/Records.swift':[
   ('var deleted: Bool\n','var removed: Bool\n'),
   ('syncedAt: Date? = nil, deleted: Bool = false)','syncedAt: Date? = nil, removed: Bool = false)'),
   ('self.deleted = deleted','self.removed = removed'),
   ('var needsPost: Bool { syncedAt == nil && !rejected && !deleted }','var needsPost: Bool { syncedAt == nil && !rejected && !removed }'),
   ('var needsDelete: Bool { deleted && !deleteSynced }','var needsDelete: Bool { removed && !deleteSynced }'),
   ('/// - `syncedAt == nil && !rejected && !deleted`  → pending POST','/// - `syncedAt == nil && !rejected && !removed`  → pending POST'),
   ('/// - `deleted && !deleteSynced`                   → pending DELETE','/// - `removed && !deleteSynced`                   → pending DELETE'),
   ('`syncedAt` is nil until the server has acknowledged the row. `deleted` is a soft flag, matching the server.','`syncedAt` is nil until the server has acknowledged the row. `removed` is the soft-delete flag (named to avoid CoreData\'s reserved `isDeleted`).'),
 ],
 'Sources/Models/Converters.swift':[('guard !deleted else { return nil }','guard !removed else { return nil }')],
 'Sources/Sync/SyncClient.swift':[
   ('predicate: #Predicate { $0.syncedAt == nil && !$0.rejected && !$0.deleted }','predicate: #Predicate { $0.syncedAt == nil && !$0.rejected && !$0.removed }'),
   ('predicate: #Predicate { $0.deleted && !$0.deleteSynced }','predicate: #Predicate { $0.removed && !$0.deleteSynced }'),
   ('existing.deleted = true','existing.removed = true'),
   ('syncedAt: now(), deleted: dto.deleted)','syncedAt: now(), removed: dto.deleted)'),
 ],
 'Sources/Screens/TodayScreen.swift':[
   ('#Predicate<CompletionRecord> { !$0.deleted }','#Predicate<CompletionRecord> { !$0.removed }'),
   ('record.deleted = true','record.removed = true'),
 ],
 'Tests/SyncTests.swift':[
   ('syncedAt: synced ? Date() : nil, deleted: deleted)','syncedAt: synced ? Date() : nil, removed: deleted)'),
   ('XCTAssertTrue(r.deleted)','XCTAssertTrue(r.removed)'),
   ('XCTAssertFalse(r1.deleted)','XCTAssertFalse(r1.removed)'),
   ('XCTAssertTrue(r2.deleted)','XCTAssertTrue(r2.removed)'),
   ('predicate: #Predicate { !$0.deleted }','predicate: #Predicate { !$0.removed }'),
 ],
 'Tests/SeedTests.swift':[
   ('XCTAssertFalse(record.deleted)','XCTAssertFalse(record.removed)'),
   ('record.deleted = true','record.removed = true'),
 ],
}
for f,subs in files.items():
    s=open(f).read()
    for a,b in subs:
        assert a in s, (f,a)
        s=s.replace(a,b)
    open(f,'w').write(s)
print("renamed ok")
