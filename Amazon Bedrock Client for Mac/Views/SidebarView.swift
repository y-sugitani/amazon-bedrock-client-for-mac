//
//  SidebarView.swift
//  Amazon Bedrock Client for Mac
//
//  Created by Na, Sanghwa on 2023/10/06.
//

import SwiftUI
import AppKit  // Import AppKit for file operations

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    @Binding var menuSelection: SidebarSelection?
    @ObservedObject var chatManager: ChatManager = ChatManager.shared

    @State private var organizedChatModels: [String: [ChatModel]] = [:]
    @State private var selectionId = UUID() // Add a unique ID for the selection state
    @State private var hoverStates: [String: Bool] = [:] // Dictionary to track hover state for each chat

    @State var buttonHover = false

    // Timer to update chat list periodically
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        List {
            newChatSection
            ForEach(organizedChatModels.keys.sorted().reversed(), id: \.self) { dateKey in
                Section(header: Text(dateKey)) {
                    ForEach(organizedChatModels[dateKey] ?? [], id: \.self) { chat in
                        chatRowView(for: chat)
                            .contextMenu {
                                Button("Delete Chat", action: {
                                    deleteChat(chat)
                                })
                                Button("Export Chat as Text", action: {
                                    exportChatAsTextFile(chat)
                                })
                            }
                    }
                }
            }
        }
        .onReceive(timer) { _ in
             organizeChatsByDate() // Refresh the chat list every minute
         }
        .id(selectionId) // Use the unique ID here to force a redraw
        .listStyle(SidebarListStyle())
        .frame(minWidth: 100, idealWidth: 150, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: organizeChatsByDate)
        .onChange(of: chatManager.chats, perform: { _ in organizeChatsByDate() })
    }

    var newChatSection: some View {
        Button(action: {
            createNewChat()
            // Reset button hover state after action is performed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.buttonHover = false
            }
        }) {
            HStack {
                Image(systemName: "square.and.pencil")
                    .font(.title) // Increase the size of the icon

                Text("New Chat")
                    .font(.title2) // Increase the text size
                    .fontWeight(.medium) // Adjust the font weight as needed
            }
            .padding(.horizontal, 4) // Reduce horizontal padding
            .padding(.vertical) // Default vertical padding
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle()) // Extend the clickable area to the entire bounds of the button
        }
        .buttonStyle(PlainButtonStyle())
//        .onHover { hover in
//            buttonHover = hover
//        }
        .background(buttonHover ? Color.gray.opacity(0.2) : Color.clear)
        .cornerRadius(8)
    }

    private func createNewChat() {
        if let modelSelection = menuSelection, case .chat(let model) = modelSelection {
            var newChat = chatManager.createNewChat(modelId: model.id, modelName: model.name)
            // Ensure the last message date is set to now so it appears at the top
            newChat.lastMessageDate = Date()
            organizeChatsByDate()
            selection = .chat(newChat)
            selectionId = UUID() // Update the ID to force a redraw
        }
    }

    private func organizeChatsByDate() {
        let calendar = Calendar.current
        
        // Sort chats by their last message date in descending order
        let sortedChats = chatManager.chats.sorted { $0.lastMessageDate > $1.lastMessageDate }
        
        // Group sorted chats by their date components
        let groupedChats = Dictionary(grouping: sortedChats) { chat -> DateComponents in
            calendar.dateComponents([.year, .month, .day], from: chat.lastMessageDate)
        }
        
        // Convert DateComponents back to Dates to sort them
        let sortedDates = groupedChats.keys.compactMap { calendar.date(from: $0) }.sorted(by: >)
        
        // Reconstruct the organizedChatModels using the sorted dates
        organizedChatModels = [:]  // Clear the existing dictionary
        for date in sortedDates {
            let key = formatDate(date)
            if let chatsForDate = groupedChats[calendar.dateComponents([.year, .month, .day], from: date)] {
                organizedChatModels[key] = chatsForDate
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM dd, yyyy"
        return dateFormatter.string(from: date)
    }

    func chatRowView(for chat: ChatModel) -> some View {
        HStack {
            Circle() // Placeholder for profile picture or status indicator
                .frame(width: 10, height: 10)
                .foregroundColor(.blue) // This could be dynamic based on chat status
            
            VStack(alignment: .leading) {
                Text(chat.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(chat.description)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if chatManager.getIsLoading(for: chat.chatId) {
                ProgressView() // Shows a loading indicator if the chat is loading
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8) // Reduce horizontal padding
        .contentShape(Rectangle()) // Extend the clickable area to the entire bounds of the row
        .background(hoverStates[chat.chatId, default: false] || selection == .chat(chat) ? Color.gray.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onHover { hover in
            hoverStates[chat.chatId] = hover
        }
        .onTapGesture { selection = .chat(chat) }
    }

    private func deleteChat(_ chat: ChatModel) {
        // Update hover states in case the deleted chat was being hovered
        hoverStates[chat.chatId] = false
        // Perform the delete operation
        if let index = chatManager.chats.firstIndex(where: { $0.chatId == chat.chatId }) {
            chatManager.chats.remove(at: index)
        }
        selection = .newChat
        // Re-organize the chat list to reflect the changes
        organizeChatsByDate()
    }

    private func exportChatAsTextFile(_ chat: ChatModel) {
        let chatMessages = chatManager.chatMessages[chat.chatId] ?? []
        
        let fileContents = chatMessages.map { "\($0.sentTime): \($0.user): \($0.text)" }.joined(separator: "\n")

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "\(chat.title)-ChatHistory.txt"

        savePanel.begin { response in
            if response == .OK {
                guard let url = savePanel.url else { return }
                do {
                    try fileContents.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to save chat history: \(error)")
                }
            }
        }
    }
}
