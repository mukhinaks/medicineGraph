using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using Fusion.Mathematics;

namespace GraphVis
{
	public class StanfordNetwork : GraphFromFile
	{
		const int maxNodes = 50000;



		public override void ReadFromFile(string pathEdge)
		{
			string pathNode = "../../../../medicine/nodes.txt";
			var lines = File.ReadAllLines(pathNode);
			Dictionary<int, int> nodeId_NodeNumber = new Dictionary<int, int>();
			List<int> nodeDegrees = new List<int>();

			int numOfNodesAdded = 0;
			if (lines.Length > 0)
			{
				// construct dictionary to convert id to number:
				foreach (var line in lines)
				{
					if (line.ElementAt(0) != '#')
					{
						string[] parts;
						parts = line.Split(new Char[] { '\t', ',' });
						int index1 = int.Parse(parts[0]);
						string text = parts[4];
						int colorID = int.Parse(parts[3]);

						if (!nodeId_NodeNumber.ContainsKey(index1))
						{
							nodeId_NodeNumber.Add(index1, numOfNodesAdded);
							++numOfNodesAdded;
						}
						Color color = Color.AliceBlue;
						switch (colorID)
						{
							case	1:
							{
								color = new Color(213,94,0);
								break;
							}
							case	2:
							{
								color = new Color(204, 121,167);
								break;
							}
							case 3:
							{
								color =  new Color(0,114,178);
								break;
							}
						}
						
						AddNode(new NodeWithText(text, 20.0f, color));
						nodeDegrees.Add(0);
					}
				}


				int numNodes = maxNodes < nodeId_NodeNumber.Count ? maxNodes : nodeId_NodeNumber.Count;
				//// add nodes:
				//for (int i = 0; i < numNodes; ++i)
				//{
					
				//}

				// add edges:
				lines = File.ReadAllLines(pathEdge);
				Console.WriteLine("checking...");
				foreach ( var line in lines )
				{
					if (line.ElementAt(0) != '#')
					{
						string[] parts;
						parts = line.Split(new Char[] {'\t', ' '});
						int index1 = nodeId_NodeNumber[int.Parse(parts[0])];
						int index2 = nodeId_NodeNumber[int.Parse(parts[1])];
						float value = (float) Math.Sqrt( float.Parse(parts[2]));
						
						if (index1 != index2)
						{
							if ( index1 < numNodes && index2 < numNodes ) {
								AddEdge(index1, index2);
								//AddEdge(index1, index2, value);
								nodeDegrees[index1] += 1;
								nodeDegrees[index2] += 1;
								//((NodeWithText)Nodes[index1]).Text = "id=" + parts[0];
								//((NodeWithText)Nodes[index2]).Text = "id=" + parts[1];
							}
						}
						else
						{
							Console.WriteLine("bad edge " + line);
						}
						
					}
				}
				Console.WriteLine("checked");

				int maxDegree = 0;
				foreach (var d2 in nodeDegrees)
				{
					int degree = d2/2;
					maxDegree = degree > maxDegree ? degree : maxDegree;	
				}
				Console.WriteLine("max degree = " + maxDegree);
			}
		}
	}
}
