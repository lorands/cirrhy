// Copyright 2026 Lóránd Somogyi
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/// Cirrhy's storage and merge engine.
///
/// Pure Dart with no UI dependencies, so it can be tested without a running
/// app. It is the part that can lose user data, which is why DESIGN.md §9 puts
/// it first.
///
/// One file is edited on up to five devices and synced by a service we neither
/// control nor know about. That cannot be solved at the file layer — locking
/// and mtime comparison both fail once an opaque sync client is involved — so
/// it is solved at the record layer by a merge that understands the data.
library;

export 'src/codec.dart'
    show DocumentCodec, DocumentFormatException, JsonDocumentCodec, contentHash;
export 'src/document.dart' show CirrhyDocument;
export 'src/merge.dart' show defaultHistoryLimit, mergeDocuments, mergeRecord;
export 'src/records.dart'
    show
        Client,
        Project,
        CirrhyRecord,
        RecordVersion,
        RelocatableRecord,
        RunningTimer,
        Task,
        TimeEntry,
        Tombstone,
        uuidV4;
export 'src/store.dart'
    show
        DocumentBackup,
        DocumentRepository,
        DocumentStore,
        SaveBlockedException,
        StoredBytes;
