import Foundation

protocol PolicyStore: AnyObject {
    var policy: ParentalPolicy { get }
    func load()
    func save(_ policy: ParentalPolicy)
    func resetToDefaults()
}

final class LocalPolicyStore: PolicyStore, ObservableObject {
    @Published private(set) var policy: ParentalPolicy = .default

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = AppGroupStore.sharedDefaults) {
        self.defaults = defaults
        load()
    }

    func load() {
        guard let data = defaults.data(forKey: AppGroupStore.Key.parentalPolicy),
              let decoded = try? decoder.decode(ParentalPolicy.self, from: data) else {
            policy = .default
            return
        }
        policy = decoded
    }

    func save(_ policy: ParentalPolicy) {
        var updated = policy
        updated.updatedAt = Date()
        self.policy = updated
        if let data = try? encoder.encode(updated) {
            defaults.set(data, forKey: AppGroupStore.Key.parentalPolicy)
        }
    }

    func resetToDefaults() {
        save(.default)
    }
}
