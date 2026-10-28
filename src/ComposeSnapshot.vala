/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

namespace ButMail {
    public class ComposeSnapshot : Object {
        public Folder account;
        public string to;
        public string cc;
        public string bcc;
        public string subject;
        public string html;
        public string? reply_id;
        public string? draft_uid;
        public Folder? draft_account;
        public GenericArray<Camel.MimePart> parts = new GenericArray<Camel.MimePart> ();
        public GenericArray<File> files = new GenericArray<File> ();

        public ComposeSnapshot (Folder account, string to, string cc, string bcc, string subject, string html,
                                GenericArray<File> attachments, GenericArray<Camel.MimePart> preserved, string? reply_id, string? draft_uid, Folder? draft_account) {
            this.account = account;
            this.to = to; this.cc = cc; this.bcc = bcc;
            this.subject = subject; this.html = html;
            this.reply_id = reply_id; this.draft_uid = draft_uid; this.draft_account = draft_account;
            foreach (var part in preserved.data) { parts.add (part); }
            foreach (var file in attachments.data) { files.add (file); }
        }
    }
}
