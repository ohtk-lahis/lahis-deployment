// Reusable pure request builder for this experiment. Run with connector readbacks.
// Caller must assert the target is the disposable trial, and supply revision control.
({
  rebuild(model, current, original) {
    const end = current.tabs[0].body.content.at(-1).endIndex - 1;
    const requests = end > 1 ? [{deleteContentRange:{range:{startIndex:1,endIndex:end}}}] : [];
    for (const b of [...model.blocks].reverse()) {
      if (b.kind === 'table') {
        requests.push({insertTable:{rows:b.rows.length,columns:b.rows[0].length,location:{index:1}}});
      } else if (b.kind === 'image') {
        const obj = original.tabs[0].inlineObjects[b.imageId].inlineObjectProperties.embeddedObject;
        const w = obj.size.width.magnitude, h = obj.size.height.magnitude;
        const scale = Math.min(432/w, 288/h);
        requests.push({insertText:{location:{index:1},text:'\n'}});
        requests.push({insertInlineImage:{location:{index:1},uri:obj.imageProperties.contentUri,
          objectSize:{width:{magnitude:w*scale,unit:'PT'},height:{magnitude:h*scale,unit:'PT'}}}});
      } else requests.push({insertText:{location:{index:1},text:b.text+'\n'}});
    }
    return requests;
  },
  fillTables(model, doc) {
    const tables = doc.tabs[0].body.content.filter(e=>e.table);
    const models = model.blocks.filter(b=>b.kind==='table');
    const requests = [];
    tables.forEach((t,i)=>t.table.tableRows.forEach((r,j)=>r.tableCells.forEach((c,k)=>{
      requests.push({insertText:{location:{index:c.content[0].startIndex},text:models[i].rows[j][k]}});
    })));
    return requests.sort((a,b)=>b.insertText.location.index-a.insertText.location.index);
  },
  style(model, doc) {
    const content = doc.tabs[0].body.content;
    const end = content.at(-1).endIndex-1;
    const range = {startIndex:1,endIndex:end};
    const pt = magnitude=>({magnitude,unit:'PT'});
    const requests = [
      {deleteParagraphBullets:{range}},
      {updateTextStyle:{range,textStyle:{weightedFontFamily:{fontFamily:model.font},fontSize:pt(16),bold:false,italic:false,foregroundColor:{color:{rgbColor:{}}}},fields:'weightedFontFamily,fontSize,bold,italic,foregroundColor'}},
      {updateParagraphStyle:{range,paragraphStyle:{namedStyleType:'NORMAL_TEXT',lineSpacing:115,spaceAbove:pt(0),spaceBelow:pt(6),indentStart:pt(0),indentEnd:pt(0),indentFirstLine:pt(0),keepWithNext:false,keepLinesTogether:true,alignment:'START'},fields:'namedStyleType,lineSpacing,spaceAbove,spaceBelow,indentStart,indentEnd,indentFirstLine,keepWithNext,keepLinesTogether,alignment'}},
      {updateDocumentStyle:{documentStyle:{documentFormat:{documentMode:'PAGES'},pageSize:{width:pt(595.28),height:pt(841.89)},marginTop:pt(54),marginBottom:pt(54),marginLeft:pt(54),marginRight:pt(54)},fields:'documentFormat,pageSize,marginTop,marginBottom,marginLeft,marginRight'}}
    ];
    const paras = content.filter(e=>e.paragraph);
    const find = b=>paras.find(e=>e.paragraph.elements.map(x=>x.textRun?.content||'').join('')===b.text+'\n');
    for(let i=0;i<model.blocks.length;i++) {
      const b=model.blocks[i];
      if(!b.text) continue;
      const e=find(b); if(!e) throw new Error('Missing paragraph: '+b.text);
      const r={startIndex:e.startIndex,endIndex:e.endIndex};
      if(b.kind==='heading'||b.kind==='title') {
        requests.push({updateParagraphStyle:{range:r,paragraphStyle:{namedStyleType:b.kind==='title'?'TITLE':'HEADING_1',keepWithNext:true,spaceAbove:pt(12),spaceBelow:pt(6)},fields:'namedStyleType,keepWithNext,spaceAbove,spaceBelow'}});
        requests.push({updateTextStyle:{range:r,textStyle:{fontSize:pt(b.kind==='title'?24:20),bold:true},fields:'fontSize,bold'}});
      }
      if(b.kind==='caption') requests.push({updateTextStyle:{range:r,textStyle:{fontSize:pt(14)},fields:'fontSize'}});
      if(b.kind==='caption') requests.push({updateParagraphStyle:{range:r,paragraphStyle:{alignment:'CENTER'},fields:'alignment'}});
      if(model.blocks[i+1]?.kind==='image') requests.push({updateParagraphStyle:{range:r,paragraphStyle:{keepWithNext:true},fields:'keepWithNext'}});
      if(b.kind==='number'||b.kind==='bullet') {
        const prev=model.blocks[i-1];
        if(prev?.kind===b.kind && (b.kind==='bullet'||prev.group===b.group)) continue;
        let last=b;
        for(const next of model.blocks.slice(i+1)) {
          if(next.kind!==b.kind||(b.kind==='number'&&next.group!==b.group)) break;
          last=next;
        }
        const listRange={startIndex:e.startIndex,endIndex:find(last).endIndex};
        requests.push({createParagraphBullets:{range:listRange,bulletPreset:b.kind==='number'?'NUMBERED_DECIMAL_ALPHA_ROMAN':'BULLET_DISC_CIRCLE_SQUARE'}});
        requests.push({updateParagraphStyle:{range:listRange,paragraphStyle:{indentStart:pt(24),indentFirstLine:pt(8),spaceBelow:pt(3)},fields:'indentStart,indentFirstLine,spaceBelow'}});
      }
    }
    for(const e of paras) if(e.paragraph.elements.some(x=>x.inlineObjectElement)) requests.push({updateParagraphStyle:{range:{startIndex:e.startIndex,endIndex:e.endIndex},paragraphStyle:{keepWithNext:true,alignment:'CENTER',spaceAbove:pt(6),spaceBelow:pt(3)},fields:'keepWithNext,alignment,spaceAbove,spaceBelow'}});
    for(const t of content.filter(e=>e.table)) {
      const loc={index:t.startIndex};
      requests.push({pinTableHeaderRows:{tableStartLocation:loc,pinnedHeaderRowsCount:1}});
      requests.push({updateTableRowStyle:{tableStartLocation:loc,tableRowStyle:{preventOverflow:true},fields:'preventOverflow'}});
      [42,122,323.28].forEach((w,i)=>requests.push({updateTableColumnProperties:{tableStartLocation:loc,columnIndices:[i],tableColumnProperties:{widthType:'FIXED_WIDTH',width:pt(w)},fields:'widthType,width'}}));
      requests.push({updateTableCellStyle:{tableStartLocation:loc,tableCellStyle:{paddingTop:pt(4),paddingBottom:pt(4),paddingLeft:pt(6),paddingRight:pt(6)},fields:'paddingTop,paddingBottom,paddingLeft,paddingRight'}});
      const header=t.table.tableRows[0];
      requests.push({updateTextStyle:{range:{startIndex:header.startIndex,endIndex:header.endIndex},textStyle:{bold:true},fields:'bold'}});
      requests.push({updateTableCellStyle:{tableRange:{tableCellLocation:{tableStartLocation:loc,rowIndex:0,columnIndex:0},rowSpan:1,columnSpan:3},tableCellStyle:{backgroundColor:{color:{rgbColor:{red:.91,green:.94,blue:.96}}}},fields:'backgroundColor'}});
      requests.push({updateParagraphStyle:{range:{startIndex:t.startIndex,endIndex:t.endIndex},paragraphStyle:{spaceBelow:pt(0),lineSpacing:110},fields:'spaceBelow,lineSpacing'}});
    }
    return requests;
  }
})
