#include <QHeaderView>
#include <QFileInfo>
#include <QIcon>

#include "utils/file-utils.h"
#include "repo-service.h"

#include "event-details-tree.h"

EventFileItem::EventFileItem(const QString& path, EType etype)
    : path_(path),
      etype_(etype)
{
    // setFlags(Qt::ItemIsSelectable | Qt::ItemIsEnabled);
    setEditable(false);
}

QString EventFileItem::name() const
{
    return QFileInfo(path_).fileName();
}

bool EventFileItem::isFileOpenable() const
{
    return etype_ == FILE_ADDED ||
        etype_ == FILE_MODIFIED ||
        etype_ == DIR_ADDED;
}

QVariant EventFileItem::data(int role) const
{
    if (role == Qt::DecorationRole) {
        return QIcon(::getIconByFileName(name()));
    } else if (role == Qt::DisplayRole) {
        return name();
    } else if (role == Qt::ToolTipRole) {
        return path_;
    } else {
        return QVariant();
    }
}

EventCategoryItem::EventCategoryItem(const QString& text)
    : QStandardItem(text)
{
    setFlags(Qt::ItemIsSelectable | Qt::ItemIsEnabled);
    setEditable(false);
}


EventDetailsTreeView::EventDetailsTreeView(const SeafEvent& event, QWidget *parent)
    : QTreeView(parent),
      event_(event)
{
    header()->hide();
    setExpandsOnDoubleClick(false);
#ifdef Q_WS_MAC
    this->setAttribute(Qt::WA_MacShowFocusRect, 0);
#endif

    setEditTriggers(QAbstractItemView::NoEditTriggers);
    
    connect(this, SIGNAL(doubleClicked(const QModelIndex&)),
            this, SLOT(onItemDoubleClicked(const QModelIndex&)));
}

void EventDetailsTreeView::onItemDoubleClicked(const QModelIndex& index)
{
    QStandardItem *qitem = getFileItem(index);
    if (!qitem) {
        return;
    }
    if (qitem->type() == EVENT_FILE_ITEM_TYPE) {
        EventFileItem *item = (EventFileItem *)qitem;
        if (item->isFileOpenable()) {
            RepoService::instance()->openLocalFile(event_.repo_id, item->path());
        }
    }
}

QStandardItem* EventDetailsTreeView::getFileItem(const QModelIndex& index)
{
    if (!index.isValid()) {
        return NULL;
    }
    const EventDetailsTreeModel *model = (const EventDetailsTreeModel*)index.model();
    QStandardItem *item = model->itemFromIndex(index);
    if (item->type() != EVENT_FILE_ITEM_TYPE) {
        return NULL;
    }
    return item;
}

EventDetailsTreeModel::EventDetailsTreeModel(const SeafEvent& event, QObject *parent)
    : QStandardItemModel(parent),
      event_(event)
{
}

void EventDetailsTreeModel::setCommitDetails(const CommitDetails& details)
{
    clear();

    details_ = details;

    processEventCategory(details.added_files, tr("Added files"),  EventFileItem::FILE_ADDED);
    processEventCategory(details.deleted_files, tr("Deleted files"),  EventFileItem::FILE_DELETED);
    processEventCategory(details.modified_files, tr("modified_files"),  EventFileItem::FILE_MODIFIED);
}

void EventDetailsTreeModel::processEventCategory(const std::vector<QString>& files,
                                                 const QString& desc,
                                                 EventFileItem::EType etype)
{
    if (files.empty()) {
        return;
    }

    EventCategoryItem *category = new EventCategoryItem(desc);
    appendRow(category);

    for (int i = 0, n = files.size(); i < n; i++) {
        EventFileItem *item = new EventFileItem(files[i], etype);
        category->appendRow(item);
    }
}
