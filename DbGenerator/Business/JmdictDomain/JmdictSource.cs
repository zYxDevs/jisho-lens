using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml;
using System.Xml.Linq;

namespace DbGenerator.Business.JmdictDomain;

public partial class JmdictSource
{
    private const string JmdictEntry = "entry";
    private const string JmdictEntrySequence = "ent_seq";
    private const string JmdictSense = "sense";
    private const string JmdictGlossary = "gloss";
    private const string JmdictPartOfSpeech = "pos";
    private const string JmdictCrossReference = "xref";
    private const string JmdictKanjiElement = "k_ele";
    private const string JmdictKanjiContent = "keb";
    private const string JmdictKanjiPriority = "ke_pri";
    private const string JmdictReadingElement = "r_ele";
    private const string JmdictReadingContent = "reb";
    private const string JmdictReadingPriority = "re_pri";
    private const string JmdictReadingNoKanji = "re_nokanji";

    private readonly string _archivePath;

    public JmdictSource(string path)
    {
        if (string.IsNullOrEmpty(path))
        {
            throw new ArgumentException("Path to the jmdict file can't be empty!", nameof(path));
        }

        _archivePath = path;
    }

    private async Task<Stream> GetFileStreamFromArchive()
    {
        Console.WriteLine("Getting file stream from archive...");
        await using FileStream archiveStream = new(_archivePath, FileMode.Open, FileAccess.Read);
        await using GZipStream decompressor = new(archiveStream, CompressionMode.Decompress);
        MemoryStream resultStream = new();

        Console.WriteLine("Decompressing archive...");
        await decompressor.CopyToAsync(resultStream);
        // we need to reset the filestream position because the gzip stream
        // will advance to the end of the file after copying to the file stream
        if (resultStream.Position > 0) resultStream.Seek(0, SeekOrigin.Begin);
        return resultStream;
    }

    public async Task<IEnumerable<JmdictEntry>> GetEntries()
    {
        await using Stream fileStream = await GetFileStreamFromArchive();
        XmlReaderSettings readerSettings = new()
        {
            DtdProcessing = DtdProcessing.Parse,
            MaxCharactersFromEntities = 0,
        };
        using XmlReader xmlReader = XmlReader.Create(fileStream, readerSettings);

        Console.WriteLine("Loading xml...");
        XDocument xDocument = XDocument.Load(xmlReader);
        if (xDocument.Root is null) throw new Exception("Failed to find xml root element.");

        string? entities = xDocument.DocumentType?.ToString();
        if (entities is null) throw new Exception("Failed to find xml entities.");

        // this dictionary is used to "un-resolve" the expanded entity since the XmlReader
        // doesn't allow us to do that, apparently
        Console.WriteLine("Generating entities dictionary...");
        Dictionary<string, string> posDefinition = ParseEntities(entities);

        Console.WriteLine("Parsing xml...");
        IEnumerable<JmdictEntry> entries = xDocument.Root.Elements(JmdictEntry).Select((entry, index) =>
        {
            List<XElement> readingElements = entry.Elements(JmdictReadingElement).ToList();
            return new JmdictEntry
            (
                Id: index + 1,
                EntrySequence: int.Parse(entry.Element(JmdictEntrySequence)?.Value ?? "0"),
                KanjiElements: from k in entry.Elements(JmdictKanjiElement)
                               select new Kanji(
                                   KanjiText: k.Element(JmdictKanjiContent)?.Value ?? "",
                                   Priorities: k.Elements(JmdictKanjiPriority).Select(p => p.Value)
                               ),
                ReadingElements: from r in readingElements
                                 // Exclude the node if it contains the no kanji node, and is not the only reading.
                                 // This is a behavior that seems to be implemented in Jisho (example word: 台詞).
                                 where r.Element(JmdictReadingNoKanji) is null && readingElements.Count() <= 1
                                 select new Reading(
                                     KanjiText: r.Element(JmdictReadingContent)?.Value ?? "",
                                     Priorities: r.Elements(JmdictReadingPriority).Select(p => p.Value)
                                 ),
                Senses: from s in entry.Elements(JmdictSense)
                        select new Sense(
                            Glossaries: from gloss in s.Elements(JmdictGlossary) select gloss.Value,
                            // un-resolve the pos entity so we get the shorter version
                            // we'll resolve them in flutter
                            PartsOfSpeech: s.Elements(JmdictPartOfSpeech).Select(pos => posDefinition[pos.Value]),
                            CrossReferences: s.Elements(JmdictCrossReference).Select(xref => xref.Value)
                        )
            );
        });

        return entries;
    }

    private static Dictionary<string, string> ParseEntities(string dtd)
    {
        Regex entityRegexp = EntityRegex();

        Dictionary<string, string> entities = new();
        foreach (Match? match in dtd
                     .Split("\n")
                     .Where(d => d.StartsWith("<!ENTITY"))
                     .Select(line => entityRegexp.Match(line)))
        {
            string key = match.Groups["key"].Value;
            string definition = match.Groups["definition"].Value;
            entities[definition] = key;
        }

        return entities;
    }

    [GeneratedRegex("<!ENTITY (?<key>.+) \"(?<definition>.+)\">")]
    private static partial Regex EntityRegex();
}
