import Foundation
import Testing
@testable import Project_24Z

/// Primary／Secondaryの物理Adapter排他とSession不変性を検証します。
struct CommunicationSessionAssignmentsTests {
    /// 同一物理Adapterの兼用を拒否します。
    @Test
    func sameAdapterCannotFillBothRoles() {
        let adapter = AdapterReference(opaqueID: "same")
        #expect(throws: CommunicationRuntimeError.adapterAlreadyAssigned) {
            try CommunicationSessionAssignments(sessionID: UUID(), primary: adapter, secondary: adapter, identitiesAreDistinct: false)
        }
    }

    /// Identityがunknownなら別Adapterと推測しません。
    @Test
    func unknownIdentityCannotFillBothRoles() {
        #expect(throws: CommunicationRuntimeError.adapterIdentityUnknown) {
            try CommunicationSessionAssignments(sessionID: UUID(), primary: .init(opaqueID: "a"), secondary: .init(opaqueID: "b"), identitiesAreDistinct: nil)
        }
    }

    /// Session中のAdapter交換またはrole変更を拒否します。
    @Test
    func assignmentChangeRequiresNewSession() throws {
        let assignments = try CommunicationSessionAssignments(sessionID: UUID(), primary: .init(opaqueID: "a"), secondary: .init(opaqueID: "b"), identitiesAreDistinct: true)
        #expect(throws: CommunicationRuntimeError.roleChangeRequiresNewSession) {
            try assignments.validateUnchanged(primary: .init(opaqueID: "b"), secondary: .init(opaqueID: "a"))
        }
    }
}
