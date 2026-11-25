import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../data/darma_database.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  DateTime start = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime end = DateTime(DateTime.now().year, DateTime.now().month + 1, 1);
  String period = 'month', level = 'total', kind = 'all', chart = 'bar';
  int? accountId;
  bool loading = true;
  String? error;
  Map<String,Object?> report = {};
  List<Map<String,Object?>> accounts = [];
  static const green = Color(0xFF36C982), red = Color(0xFFFF6577), blue = Color(0xFF6D9EFF);
  String fa(String s) {
    const a='0123456789', b='۰۱۲۳۴۵۶۷۸۹';
    for(var i=0;i<10;i++){s=s.replaceAll(a[i],b[i]);}
    return s;
  }
  String money(int n)=>fa(n.abs().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'),(m)=>'${m[1]},'));
  String compact(double n)=>n.abs()>=1000000000?' ${(n/1000000000).toStringAsFixed(1)}B':n.abs()>=1000000?'${(n/1000000).toStringAsFixed(1)}M':n.abs()>=1000?'${(n/1000).toStringAsFixed(0)}K':n.toStringAsFixed(0);
  String jalali(DateTime d){final j=Jalali.fromDateTime(d);return '${fa(j.year.toString())}/${fa(j.month.toString().padLeft(2,'0'))}/${fa(j.day.toString().padLeft(2,'0'))}';}
  Future<void> load() async {
    setState(()=>loading=true);
    try {
      final a=await DarmaDatabase.instance.getAccountSummaries();
      final r=await DarmaDatabase.instance.getFinancialReport(startDate:start,endDate:end,level:level,filterType:kind,selectedAccountId:accountId);
      if(!mounted)return;
      setState(() { accounts=a.where((x)=>(x['type']=='income'||x['type']=='expense')&&x['parent_id']!=null).toList(); report=r; loading=false; error=null; });
    } catch(e){if(mounted)setState(() { error=e.toString(); loading=false; });}
  }
  @override void initState(){super.initState();load();}
  void setPeriod(String p){
    final n=DateTime.now();
    setState(() {
      period=p; accountId=null;
      if(p=='month'){start=DateTime(n.year,n.month,1);end=DateTime(n.year,n.month+1,1);}
      else if(p=='quarter'){start=DateTime(n.year,n.month-2,1);end=DateTime(n.year,n.month+1,1);}
      else if(p=='year'){start=DateTime(n.year,1,1);end=DateTime(n.year+1,1,1);}
      else {start=DateTime(2000,1,1);end=DateTime(n.year,n.month,n.day+1);}
    });
    load();
  }
  int get income=>(report['income'] as num?)?.toInt()??0;
  int get expense=>(report['expense'] as num?)?.toInt()??0;
  int get count=>(report['transaction_count'] as num?)?.toInt()??0;
  List<Map<String,Object?>> get rows=>((report['breakdown'] as List?)??[]).whereType<Map<String,Object?>>().toList();
  List<Map<String,Object?>> get trends=>((report['trend'] as List?)??[]).whereType<Map<String,Object?>>().toList();

  @override Widget build(BuildContext context){
    final net=income-expense;
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.fromLTRB(14,12,14,110),children:[
      Row(children:[Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:blue.withValues(alpha:.14),borderRadius:BorderRadius.circular(15)),child:const Icon(Icons.query_stats,color:blue,size:26)),
        const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('مرکز گزارش‌های مالی',style:Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
          const Text('تحلیل درآمد، هزینه و جریان مالی',style:TextStyle(fontSize:11,color:Colors.grey))])),
        IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
      const SizedBox(height:14),
      card('بازه گزارش',Icons.calendar_month,Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Wrap(spacing:6,runSpacing:6,children:[
          chip('این ماه','month'),chip('سه ماه اخیر','quarter'),chip('امسال','year'),chip('کل دوره','all'),
          ActionChip(label:const Text('بازه دلخواه'),avatar:const Icon(Icons.date_range,size:17),onPressed:()async{
            final picked=await showDateRangePicker(context:context,firstDate:DateTime(2000),lastDate:DateTime.now().add(const Duration(days:365)),initialDateRange:DateTimeRange(start:start,end:end.subtract(const Duration(days:1))));
            if(picked!=null){setState(() { start=picked.start; end=picked.end.add(const Duration(days:1)); period='custom'; });load();}
          })]),
        const SizedBox(height:8),
        Text('${jalali(start)} تا ${jalali(end.subtract(const Duration(days:1)))}',textAlign:TextAlign.center,style:TextStyle(color:Theme.of(context).colorScheme.primary,fontWeight:FontWeight.bold))
      ])),
      const SizedBox(height:10),
      card('تنظیمات تحلیل',Icons.tune,Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('سطح گزارش',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),
        SegmentedButton<String>(showSelectedIcon:false,segments:const[ButtonSegment(value:'total',label:Text('کل')),ButtonSegment(value:'main',label:Text('معین')),ButtonSegment(value:'detail',label:Text('تفصیلی'))],selected:{level},onSelectionChanged:(v){setState(()=>level=v.first);load();}),
        const SizedBox(height:12),const Text('نوع گردش',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),
        SegmentedButton<String>(showSelectedIcon:false,segments:const[ButtonSegment(value:'all',label:Text('همه')),ButtonSegment(value:'income',label:Text('درآمد')),ButtonSegment(value:'expense',label:Text('هزینه'))],selected:{kind},onSelectionChanged:(v){setState(()=>kind=v.first);load();}),
        const SizedBox(height:12),const Text('فیلتر حساب',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),
        DropdownButtonFormField<int?>(value:accountId,isExpanded:true,decoration:const InputDecoration(border:OutlineInputBorder(),contentPadding:EdgeInsets.symmetric(horizontal:10,vertical:8)),
          items:[const DropdownMenuItem<int?>(value:null,child:Text('همه حساب‌ها')),...accounts.map((a)=>DropdownMenuItem<int?>(value:a['id'] as int,child:Text(a['name'] as String)))],
          onChanged:(v){setState(()=>accountId=v);load();})])),
      const SizedBox(height:14),
      if(loading)const Padding(padding:EdgeInsets.all(35),child:Center(child:CircularProgressIndicator()))
      else if(error!=null)card('خطا',Icons.error_outline,Column(children:[Text(error!),FilledButton.tonal(onPressed:load,child:const Text('تلاش مجدد'))]))
      else ...[
        Text('خلاصه عملکرد',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w900)),
        const SizedBox(height:8),
        GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,mainAxisSpacing:8,crossAxisSpacing:8,childAspectRatio:1.55,children:[
          metric('مجموع درآمد',income,green,Icons.south_west),metric('مجموع هزینه',expense,red,Icons.north_east),
          metric('خالص جریان نقدی',net,net>=0?green:red,Icons.account_balance_wallet),metric('تعداد تراکنش‌ها',count,blue,Icons.receipt_long)]),
        const SizedBox(height:12),
        card('ترکیب درآمد و هزینه',Icons.donut_large,Column(children:[
          Align(alignment:Alignment.centerLeft,child:chartPicker()),const SizedBox(height:12),
          SizedBox(height:210,child:mainChart()),
          Wrap(alignment:WrapAlignment.center,spacing:14,children:[legend('درآمد',green,'${money(income)} ریال'),legend('هزینه',red,'${money(expense)} ریال')])])),
        const SizedBox(height:12),
        card(level=='total'?'سهم درآمد و هزینه':level=='main'?'تفکیک حساب‌های معین':'تفکیک حساب‌های تفصیلی',Icons.pie_chart,
          rows.isEmpty?empty('در این بازه گردش مالی وجود ندارد'):Column(children:[
            SizedBox(height:225,child:breakdownChart()),
            ...rows.take(8).map((r)=>legend(r['label'] as String,r['kind']=='income'?green:red,'${money((r['amount'] as num).toInt())} ریال'))])),
        const SizedBox(height:12),
        card('روند ماهانه',Icons.show_chart,trends.isEmpty?empty('داده‌ای برای نمایش روند وجود ندارد'):SizedBox(height:230,child:trendChart())),
        const SizedBox(height:12),
        card('جزئیات حساب‌ها',Icons.table_chart,rows.isEmpty?empty('موردی برای نمایش وجود ندارد'):Column(children:rows.map((r){
          final inc=r['kind']=='income';final amount=(r['amount'] as num).toInt();final c=(r['transaction_count'] as num?)?.toInt()??0;
          return Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Row(children:[
            Container(width:8,height:34,decoration:BoxDecoration(color:inc?green:red,borderRadius:BorderRadius.circular(5))),
            const SizedBox(width:8),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(r['label'] as String,style:const TextStyle(fontWeight:FontWeight.bold)),
              Text('${fa(c.toString())} تراکنش',style:const TextStyle(fontSize:10,color:Colors.grey))])),
            Text('${money(amount)} ریال',style:TextStyle(color:inc?green:red,fontSize:11,fontWeight:FontWeight.bold))]));}).toList()))
      ]
    ]));
  }

  Widget chip(String label,String p)=>ChoiceChip(label:Text(label),selected:period==p,onSelected:(_)=>setPeriod(p));
  Widget card(String title,IconData icon,Widget child)=>Card(clipBehavior:Clip.antiAlias,child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    Row(children:[Icon(icon,color:blue,size:19),const SizedBox(width:8),Expanded(child:Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:14)))]),
    const SizedBox(height:13),child])));
  Widget metric(String title,int value,Color color,IconData icon)=>Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(
    borderRadius:BorderRadius.circular(18),gradient:LinearGradient(colors:[color.withValues(alpha:.18),color.withValues(alpha:.05)]),border:Border.all(color:color.withValues(alpha:.2))),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
      Row(children:[Icon(icon,color:color,size:18),const SizedBox(width:5),Expanded(child:Text(title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold)))]),
      FittedBox(child:Text(money(value),style:TextStyle(color:color,fontSize:21,fontWeight:FontWeight.w900))),
      Text(title=='تعداد تراکنش‌ها'?'مورد':'ریال',style:TextStyle(color:color,fontSize:10))]));
  Widget chartPicker()=>SegmentedButton<String>(showSelectedIcon:false,segments:const[
    ButtonSegment(value:'bar',icon:Icon(Icons.bar_chart,size:18)),ButtonSegment(value:'line',icon:Icon(Icons.show_chart,size:18)),ButtonSegment(value:'pie',icon:Icon(Icons.pie_chart,size:18))],
    selected:{chart},onSelectionChanged:(v)=>setState(()=>chart=v.first));
  Widget legend(String label,Color color,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(mainAxisSize:MainAxisSize.min,children:[
    Container(width:9,height:9,decoration:BoxDecoration(color:color,shape:BoxShape.circle)),const SizedBox(width:6),Text(label,style:const TextStyle(fontSize:11)),
    if(value.isNotEmpty) ...[const SizedBox(width:5),Text(value,style:const TextStyle(fontSize:10,fontWeight:FontWeight.bold))]]));
  Widget empty(String s)=>Padding(padding:const EdgeInsets.all(25),child:Center(child:Text(s,textAlign:TextAlign.center,style:const TextStyle(color:Colors.grey))));

  Widget mainChart(){
    if(chart=='pie'){
      final vals=[if(kind!='expense'&&income>0)(income.toDouble(),green),if(kind!='income'&&expense>0)(expense.toDouble(),red)];
      if(vals.isEmpty)return empty('داده‌ای برای نمودار وجود ندارد');
      return PieChart(PieChartData(centerSpaceRadius:42,sectionsSpace:4,sections:vals.map((v)=>PieChartSectionData(value:v.$1,color:v.$2,title:'',radius:55)).toList()));
    }
    final max=math.max(income,expense).toDouble();
    if(chart=='line')return LineChart(LineChartData(minY:0,maxY:max<=0?10:max*1.2,gridData:const FlGridData(show:true,drawVerticalLine:false),borderData:FlBorderData(show:false),
      titlesData:FlTitlesData(topTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),rightTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),
        leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(v,_)=>Text(compact(v),style:const TextStyle(fontSize:9)))),
        bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,getTitlesWidget:(v,_)=>Text(v==0?'درآمد':'هزینه',style:const TextStyle(fontSize:10))))),
      lineBarsData:[if(kind!='expense')LineChartBarData(spots:[FlSpot(0,income.toDouble())],color:green,barWidth:4,dotData:const FlDotData(show:true)),
        if(kind!='income')LineChartBarData(spots:[FlSpot(1,expense.toDouble())],color:red,barWidth:4,dotData:const FlDotData(show:true))]));
    return BarChart(BarChartData(maxY:max<=0?10:max*1.2,gridData:const FlGridData(show:true,drawVerticalLine:false),borderData:FlBorderData(show:false),
      titlesData:FlTitlesData(topTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),rightTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),
        leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(v,_)=>Text(compact(v),style:const TextStyle(fontSize:9)))),
        bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,getTitlesWidget:(v,_)=>Text(v==0?'درآمد':'هزینه',style:const TextStyle(fontSize:10))))),
      barGroups:[if(kind!='expense')BarChartGroupData(x:0,barRods:[BarChartRodData(toY:income.toDouble(),color:green,width:28,borderRadius:BorderRadius.circular(6))]),
        if(kind!='income')BarChartGroupData(x:1,barRods:[BarChartRodData(toY:expense.toDouble(),color:red,width:28,borderRadius:BorderRadius.circular(6))])]));
  }

  Widget breakdownChart(){
    final list=rows.take(8).toList();
    if(chart=='pie')return PieChart(PieChartData(centerSpaceRadius:35,sectionsSpace:3,sections:List.generate(list.length,(i){
      final r=list[i];return PieChartSectionData(value:(r['amount'] as num).toDouble(),color:r['kind']=='income'?green:Colors.primaries[i%Colors.primaries.length],title:'',radius:57);})));
    final max=list.fold<double>(0,(m,r)=>math.max(m,(r['amount'] as num).toDouble()));
    return BarChart(BarChartData(maxY:max<=0?10:max*1.2,alignment:BarChartAlignment.spaceAround,gridData:const FlGridData(show:true,drawVerticalLine:false),borderData:FlBorderData(show:false),
      titlesData:FlTitlesData(topTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),rightTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),
        leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(v,_)=>Text(compact(v),style:const TextStyle(fontSize:9)))),
        bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,getTitlesWidget:(v,_) {final i=v.toInt();if(i<0||i>=list.length)return const SizedBox.shrink();return SizedBox(width:60,child:Text(list[i]['label'] as String,maxLines:2,overflow:TextOverflow.ellipsis,textAlign:TextAlign.center,style:const TextStyle(fontSize:9)));}))),
      barGroups:List.generate(list.length,(i)=>BarChartGroupData(x:i,barRods:[BarChartRodData(toY:(list[i]['amount'] as num).toDouble(),color:list[i]['kind']=='income'?green:Colors.primaries[i%Colors.primaries.length],width:18,borderRadius:BorderRadius.circular(5))]))));
  }

  Widget trendChart(){
    final list=trends;final max=list.fold<double>(0,(m,r)=>math.max(m,math.max((r['income'] as num).toDouble(),(r['expense'] as num).toDouble())));
    return BarChart(BarChartData(maxY:max<=0?10:max*1.2,barGroups:List.generate(list.length,(i)=>BarChartGroupData(x:i,barsSpace:3,barRods:[
      BarChartRodData(toY:(list[i]['income'] as num).toDouble(),color:green,width:8,borderRadius:BorderRadius.circular(4)),
      BarChartRodData(toY:(list[i]['expense'] as num).toDouble(),color:red,width:8,borderRadius:BorderRadius.circular(4))])),
      gridData:const FlGridData(show:true,drawVerticalLine:false),borderData:FlBorderData(show:false),
      titlesData:FlTitlesData(topTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),rightTitles:const AxisTitles(sideTitles:SideTitles(showTitles:false)),
        leftTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,reservedSize:40,getTitlesWidget:(v,_)=>Text(compact(v),style:const TextStyle(fontSize:9)))),
        bottomTitles:AxisTitles(sideTitles:SideTitles(showTitles:true,getTitlesWidget:(v,_) {final i=v.toInt();if(i<0||i>=list.length)return const SizedBox.shrink();final k=list[i]['month_key'] as String;final d=DateTime.tryParse('$k-01');return Text(d==null?'':fa(Jalali.fromDateTime(d).month.toString()),style:const TextStyle(fontSize:9));})))));
  }
}
