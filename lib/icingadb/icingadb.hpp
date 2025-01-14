/* Icinga 2 | (c) 2012 Icinga GmbH | GPLv2+ */

#ifndef ICINGADB_H
#define ICINGADB_H

#include "icingadb/icingadb-ti.hpp"
#include "icingadb/redisconnection.hpp"
#include "base/timer.hpp"
#include "base/workqueue.hpp"
#include "icinga/customvarobject.hpp"
#include "icinga/checkable.hpp"
#include "icinga/service.hpp"
#include "icinga/downtime.hpp"
#include "remote/messageorigin.hpp"
#include <memory>

namespace icinga
{

/**
 * @ingroup icingadb
 */
class IcingaDB : public ObjectImpl<IcingaDB>
{
public:
	DECLARE_OBJECT(IcingaDB);
	DECLARE_OBJECTNAME(IcingaDB);

	IcingaDB();

	static void ConfigStaticInitialize();

	virtual void Start(bool runtimeCreated) override;
	virtual void Stop(bool runtimeRemoved) override;

private:
	void ReconnectTimerHandler();
	void TryToReconnect();
	void HandleEvents();
	void SendEvent(const Dictionary::Ptr& event);

	void PublishStatsTimerHandler();
	void PublishStats();

	/* config & status dump */
	void UpdateAllConfigObjects();
	std::vector<std::vector<intrusive_ptr<ConfigObject>>> ChunkObjects(std::vector<intrusive_ptr<ConfigObject>> objects, size_t chunkSize);
	void DeleteKeys(const std::vector<String>& keys, RedisConnection::QueryPriority priority);
	std::vector<String> GetTypeObjectKeys(const String& type);
	void InsertObjectDependencies(const ConfigObject::Ptr& object, const String typeName, std::map<String, std::vector<String>>& hMSets,
			std::map<String, std::vector<String>>& publishes, bool runtimeUpdate);
	void UpdateState(const Checkable::Ptr& checkable);
	void SendConfigUpdate(const ConfigObject::Ptr& object, bool runtimeUpdate);
	void CreateConfigUpdate(const ConfigObject::Ptr& object, const String type, std::map<String, std::vector<String>>& hMSets,
			std::map<String, std::vector<String>>& publishes, bool runtimeUpdate);
	void SendConfigDelete(const ConfigObject::Ptr& object);
	void SendStatusUpdate(const ConfigObject::Ptr& object, const CheckResult::Ptr& cr, StateType type);

	void SendSentNotification(
		const Notification::Ptr& notification, const Checkable::Ptr& checkable, const std::set<User::Ptr>& users,
		NotificationType type, const CheckResult::Ptr& cr, const String& author, const String& text
	);

	void SendStartedDowntime(const Downtime::Ptr& downtime);
	void SendRemovedDowntime(const Downtime::Ptr& downtime);
	void SendAddedComment(const Comment::Ptr& comment);
	void SendRemovedComment(const Comment::Ptr& comment);
	void SendFlappingChanged(const Checkable::Ptr& checkable, const Value& value);
	void SendNextUpdate(const Checkable::Ptr& checkable);
	void SendAcknowledgementSet(const Checkable::Ptr& checkable, const String& author, const String& comment, AcknowledgementType type, bool persistent, double expiry);
	void SendAcknowledgementCleared(const Checkable::Ptr& checkable, const String& removedBy);

	std::vector<String> UpdateObjectAttrs(const ConfigObject::Ptr& object, int fieldType, const String& typeNameOverride);
	Dictionary::Ptr SerializeState(const Checkable::Ptr& checkable);

	/* Stats */
	Dictionary::Ptr GetStats();

	/* utilities */
	static String FormatCheckSumBinary(const String& str);
	static String FormatCommandLine(const Value& commandLine);
	static long long TimestampToMilliseconds(double timestamp);

	static String GetObjectIdentifier(const ConfigObject::Ptr& object);
	static String GetEnvironment();
	static Dictionary::Ptr SerializeVars(const CustomVarObject::Ptr& object);

	static String HashValue(const Value& value);
	static String HashValue(const Value& value, const std::set<String>& propertiesBlacklist, bool propertiesWhitelist = false);

	static String GetLowerCaseTypeNameDB(const ConfigObject::Ptr& obj);
	static bool PrepareObject(const ConfigObject::Ptr& object, Dictionary::Ptr& attributes, Dictionary::Ptr& checkSums);

	static void StateChangeHandler(const ConfigObject::Ptr& object);
	static void StateChangeHandler(const ConfigObject::Ptr& object, const CheckResult::Ptr& cr, StateType type);
	static void VersionChangedHandler(const ConfigObject::Ptr& object);
	static void DowntimeStartedHandler(const Downtime::Ptr& downtime);
	static void DowntimeRemovedHandler(const Downtime::Ptr& downtime);

	static void NotificationSentToAllUsersHandler(
		const Notification::Ptr& notification, const Checkable::Ptr& checkable, const std::set<User::Ptr>& users,
		NotificationType type, const CheckResult::Ptr& cr, const String& author, const String& text
	);

	static void CommentAddedHandler(const Comment::Ptr& comment);
	static void CommentRemovedHandler(const Comment::Ptr& comment);
	static void FlappingChangedHandler(const Checkable::Ptr& checkable, const Value& value);
	static void NewCheckResultHandler(const Checkable::Ptr& checkable);
	static void AcknowledgementSetHandler(const Checkable::Ptr& checkable, const String& author, const String& comment, AcknowledgementType type, bool persistent, double expiry);
	static void AcknowledgementClearedHandler(const Checkable::Ptr& checkable, const String& removedBy);

	void AssertOnWorkQueue();

	void ExceptionHandler(boost::exception_ptr exp);

	Timer::Ptr m_StatsTimer;
	Timer::Ptr m_ReconnectTimer;
	WorkQueue m_WorkQueue;

	String m_PrefixConfigObject;
	String m_PrefixConfigCheckSum;
	String m_PrefixStateObject;

	bool m_ConfigDumpInProgress;
	bool m_ConfigDumpDone;

	RedisConnection::Ptr m_Rcon;
};
}

#endif /* ICINGADB_H */
